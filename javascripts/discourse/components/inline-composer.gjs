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
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";

export default class InlineComposer extends Component {
  @service inlineComposer;
  @service modal;

  @tracked composerContent;
  @tracked sequence = 0;
  draftKey = `post_${this.args.post.id}`;

  constructor() {
    super(...arguments);
    this.getRawPost();
    this.loadDraft();
  }

  async getRawPost() {
    try {
      const res = await ajax(`/posts/${this.args.post.id}.json`);
      this.composerContent = res.raw;
    } catch (e) {
      popupAjaxError(e);
    }
  }

  @action
  async editPost(data) {
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
      Draft.clear(this.draftKey, this.sequence);
      await this.getRawPost();
    } catch (e) {
      popupAjaxError(e);
    }
  }

  async loadDraft() {
    try {
      const draft = await Draft.get(this.draftKey);
      if (draft.draft && draft.draft.reply) {
        this.composerContent = JSON.parse(draft.draft.reply);
      }
    } catch {
      // no draft yet
    }
  }

  registerAPI(api) {
    this.formGet = api.get;
    this.formApi = api;
  }

  @action
  onContentSet(value, { set }) {
    set("content", value);
    this.scheduleDraftSave(value);
  }

  scheduleDraftSave(value) {
    debounce(this, this.saveDraft, value, 1000);
  }

  async saveDraft(value) {
    this.sequence++;
    const data = { reply: value, action: "edit_post" };
    try {
      await Draft.save(
        this.draftKey,
        this.sequence,
        data,
        this.messageBus.clientId
      );
    } catch (e) {
      await this.loadDraft();
    }
  }

  cancelComposer() {
    this.skipAutoSave = true;

    cancel(this._saveDraftDebounce);

    return new Promise((resolve) => {
      if (this.formApi?.isDirty) {
        this.modal.show(DiscardDraftModal, {
          model: {
            confirmMessageKey: "post.cancel_composer.confirm_edit",
            discardButtonKey: "post.cancel_composer.discard_edit",
            onDestroyDraft: () => {
              this.inlineComposer.stopEditing(
                this.inlineComposer.editingPostId
              );
              resolve(true);
            },
            onCancelDiscard: () => resolve(false),
          },
        });
      } else {
        this.destroyDraft()
          .then(() => {
            this.model.clearState();
            this.close();
          })
          .finally(() => {
            resolve();
          });
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

  <template>
    {{#if (eq this.inlineComposer.editingPostId @post.id)}}
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

        <form.Submit @label={{themePrefix "composer_edit_text"}} />
        <DButton
          @action={{this.cancelComposer}}
          class="discard-button btn-transparent"
          @title="composer.cancel_edit"
          @label="composer.cancel_edit"
        />
      </Form>
    {{else}}
      {{yield}}
    {{/if}}
  </template>
}
