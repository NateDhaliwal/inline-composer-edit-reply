import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { action } from "@ember/object";
import { cancel, debounce } from "@ember/runloop";
import { service } from "@ember/service";
import Form from "discourse/components/form";
import DiscardDraftModal from "discourse/components/modal/discard-draft";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import Draft from "discourse/models/draft";
import { and, eq, not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import { isundefnull } from "../helpers/is-undefined-or-null";

export default class InlineComposer extends Component {
  @service inlineComposer;
  @service modal;
  @service messageBus;
  @service toasts;
  @service dialog;

  @tracked composerContent;
  @tracked sequence = 0;
  @tracked draftForceSave = false;
  draftKey = `post_${this.args.post.id}`;

  constructor() {
    super(...arguments);
    this.getRawPost();
  }

  async getRawPost() {
    this.skipAutoSave = false; // Reset at the start
    const draft = await this.loadDraft();
    if (draft !== null && draft !== undefined) {
      this.composerContent = draft;
      return;
    } else if (draft === null) {
      try {
        const res = await ajax(`/posts/${this.args.post.id}.json`);
        this.composerContent = res.raw;
      } catch (e) {
        popupAjaxError(e);
      }
    }
  }

  @action
  async editPost(data) {
    if (this.skipAutoSave) {
      return;
    }
    cancel(this._saveDraftDebounce);
    const newContent = data.content;
    try {
      await ajax(`/posts/${this.args.post.id}.json`, {
        type: "PUT",
        data: {
          post: {
            raw: newContent,
          },
        },
      });
      this.inlineComposer.stopEditing(this.args.post.id);
      await Draft.clear(this.draftKey, this.sequence);
      this.composerContent = newContent; // We update the composer to the new value
    } catch (e) {
      popupAjaxError(e);
    }
  }

  async loadDraft() {
    try {
      const draft = await Draft.get(this.draftKey);
      this.sequence = draft.draft_sequence;
      if (draft.draft) {
        return JSON.parse(draft.draft).reply;
      } else {
        return null;
      }
    } catch (e) {
      if (e.status === 404) {
        return null; // No draft found
      }
      if (e.status === 0) {
        // Network error
        return undefined;
      }
    }
  }

  // Form API
  @action
  registerAPI(api) {
    console.log("Fire");
    this.formApi = api;
  }

  @action
  onContentSet(value, { set }) {
    if (this.skipAutoSave) {
      return;
    }
    set("content", value);
    this.scheduleDraftSave(value);
  }

  scheduleDraftSave(value) {
    this._saveDraftDebounce = debounce(this, this.saveDraft, value, 1000);
  }

  async saveDraft(value, showToast = false) {
    if (this.skipAutoSave) {
      return;
    }
    this.sequence++;
    const data = {
      reply: value,
      action: "edit_post",
      original_title: this.args.post.topic.title,
      original_text: this.composerContent,
      post_id: this.args.post.id,
      category_id: this.args.post.topic.category_id,
      tags: this.args.post.topic.tags,
      archetype: "regular",
      slug: this.args.post.topic.slug,
      topic_id: this.args.post.topic_id,
    };
    try {
      await Draft.save(
        this.draftKey,
        this.sequence,
        data,
        this.messageBus.clientId,
        { forceSave: this.draftForceSave }
      );
      if (showToast) {
        // The user clicked the 'Save Draft' button
        this.toasts.success({
          duration: "short",
          data: {
            message: i18n("composer.draft_saved"),
          },
        });
        this.skipAutoSave = true;
        cancel(this._saveDraftDebounce);
      }
    } catch (e) {
      const xhr = e && e.jqXHR;
      if (
        xhr &&
        xhr.status === 409 &&
        xhr.responseJSON &&
        xhr.responseJSON.errors &&
        xhr.responseJSON.errors.length
      ) {
        // Edit conflict!
        const json = e.jqXHR.responseJSON;

        if (json.extras?.description) {
          this.dialog.alert({
            message: json.extras.description,
            buttons: [
              {
                label: i18n("composer.reload"),
                class: "btn-primary",
                action: () => window.location.reload(),
              },
              {
                label: i18n("composer.ignore"),
                class: "btn-default",
                action: () => {
                  this.draftForceSave = true;
                  this.saveDraft(value); // Force retry
                },
              },
            ],
          });
          return;
        }
      }
      const latestDraft = await this.loadDraft();
      if (latestDraft !== null) {
        this.formApi?.set("content", latestDraft);
      }
    }
  }

  @action
  cancelComposer() {
    this.skipAutoSave = true;

    cancel(this._saveDraftDebounce);

    return new Promise((resolve) => {
      if (
        this.formApi?.isDirty ||
        this.composerContent !== this.formApi?.get("content")
      ) {
        this.modal.show(DiscardDraftModal, {
          model: {
            confirmMessageKey: "post.cancel_composer.confirm_edit",
            discardButtonKey: "post.cancel_composer.discard_edit",
            onDestroyDraft: async () => {
              await Draft.clear(this.draftKey, this.sequence);
              this.inlineComposer.stopEditing(
                this.inlineComposer.editingPostId
              );
              resolve(true);
            },
            onCancelDiscard: () => {
              this.skipAutoSave = false;
              resolve(false);
            },
          },
        });
      } else {
        this.destroyDraft()
          .then(() => {
            this.inlineComposer.stopEditing(this.inlineComposer.editingPostId);
          })
          .finally(() => resolve());
      }
    });
  }

  async destroyDraft() {
    const key = this.draftKey;
    if (!key) {
      return;
    }

    await Draft.clear(key, this.sequence);
  }

  @action
  async saveDraftForm() {
    const value = this.formApi?.get("content");
    if (value !== undefined) {
      await this.saveDraft(value, true);
      this.inlineComposer.stopEditing(this.inlineComposer.editingPostId);
    }
  }

  <template>
    {{#if
      (and
        (eq this.inlineComposer.editingPostId @post.id)
        (not (isundefnull this.composerContent))
      )
    }}
      <Form
        @data={{hash content=this.composerContent}}
        @onSubmit={{this.editPost}}
        @onRegisterApi={{this.registerAPI}}
        as |form|
      >
        <form.Field
          @name="content"
          @validation="required"
          @title="&nbsp;"
          @type="composer"
          @onSet={{this.onContentSet}}
          as |field|
        >
          <field.Control @preview={{settings.show_preview}} />
        </form.Field>

        <div class="button-row">
          <form.Submit @label={{themePrefix "composer_edit_text"}} />
          <DButton
            @action={{this.cancelComposer}}
            class="discard-button btn-transparent"
            @title="composer.cancel_edit"
            @label="composer.cancel_edit"
          />
          <DButton
            @action={{this.saveDraftForm}}
            class="btn-transparent"
            @title={{themePrefix "save_draft_button_text"}}
            @label={{themePrefix "save_draft_button_text"}}
          />
        </div>
      </Form>
    {{else}}
      {{yield}}
    {{/if}}
  </template>
}
