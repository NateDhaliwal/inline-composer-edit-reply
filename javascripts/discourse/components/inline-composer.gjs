import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { cancel, debounce } from "@ember/runloop";
import { service } from "@ember/service";
import Form from "discourse/components/form";
import DiscardDraftModal from "discourse/components/modal/discard-draft";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import Draft from "discourse/models/draft";
import { eq, not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DConditionalLoadingSpinner from "discourse/ui-kit/d-conditional-loading-spinner";
import { i18n } from "discourse-i18n";
import { isundefnull } from "../helpers/isundefnull";

export default class InlineComposer extends Component {
  @service inlineComposer;
  @service modal;

  @tracked formApi;
  @tracked cancelling = false;

  @action
  async editPost(data) {
    cancel(this._saveDraftDebounce);
    const newContent = data.content;
    try {
      await ajax(`/posts/${this.args.post.id}.json`, {
        type: "PUT",
        data: {
          post: {
            raw: newContent,
            edit_reason: data.editReason,
          },
        },
      });
      await this.inlineComposer.clearDraft(this.args.post.id);
      this.inlineComposer.stopEditing(this.formApi.get("content"), {
        clearCache: true,
      });
    } catch (e) {
      popupAjaxError(e);
    }
  }

  // Form API
  @action
  registerAPI(api) {
    this.formApi = api;
  }

  @action
  onContentSet(value, { set }) {
    if (this.inlineComposer.conflict) {
      return;
    }
    set("content", value);
    this.scheduleDraftSave(value);
  }

  scheduleDraftSave() {
    if (this.cancelling) {
      return;
    }
    this._saveDraftDebounce = debounce(this, this.performDraftSave, 1000);
  }

  @action
  async performDraftSave() {
    cancel(this._saveDraftDebounce);
    if (this.inlineComposer.editingPostId !== this.args.post.id) {
      return;
    }
    const value = this.formApi?.get("content");
    if (value !== undefined && value !== this.inlineComposer.composerContent) {
      await this.inlineComposer.saveDraft(value, this.args.post, false);
    }
  }

  @action
  cancelComposer() {
    this.cancelling = true;
    cancel(this._saveDraftDebounce);

    return new Promise((resolve) => {
      // When cancelling a composer with a pre-loaded draft, the modal does not appear.
      // By fetching the raw post and comparing it, we ensure that is is shown.
      ajax(`/posts/${this.args.post.id}.json`).then((res) => {
        if (
          this.formApi?.isDirty ||
          this.inlineComposer.composerContent !==
            this.formApi?.get("content") ||
          res.raw !== this.formApi.get("content")
        ) {
          this.modal.show(DiscardDraftModal, {
            model: {
              confirmMessageKey: "post.cancel_composer.confirm_edit",
              discardButtonKey: "post.cancel_composer.discard_edit",
              onDestroyDraft: async () => {
                const postId = this.args.post.id;

                await this.inlineComposer.clearDraft(postId);

                this.inlineComposer.stopEditing(undefined, {
                  clearCache: true,
                });

                this.cancelling = false;

                resolve(true);
              },
              onCancelDiscard: () => {
                this.cancelling = false;
                resolve(false);
              },
            },
          });
        } else {
          this.inlineComposer.stopEditing(this.formApi.get("content"));
          this.cancelling = false;
          resolve();
        }
      });
    });
  }

  @action
  async saveDraftForm() {
    const value = this.formApi?.get("content");
    if (value !== undefined) {
      cancel(this._saveDraftDebounce);
      // Check if true/false in case of 409 conflicts
      const saveSuccess = await this.inlineComposer.saveDraft(
        value,
        this.args.post,
        true
      );
      if (saveSuccess) {
        this.inlineComposer.stopEditing(this.formApi.get("content"), {
          saved: true,
        });
      }
    }
  }

  @action
  handleKeyDown(event) {
    if ((event.ctrlKey || event.metaKey) && event.key === "Enter") {
      event.preventDefault();
      this.formApi?.submit();
    }
  }

  get height() {
    return settings.manually_set_composer_height
      ? parseInt(settings.composer_height, 10)
      : (parseInt(localStorage.getItem("discourse_composerHeight"), 10) ??
          parseInt(settings.composer_height, 10));
  }

  <template>
    {{#if (eq this.inlineComposer.editingPostId @post.id)}}
      {{#if this.inlineComposer.loading}}
        <DConditionalLoadingSpinner
          @condition={{this.inlineComposer.loading}}
        />
      {{else}}
        {{#if (not (isundefnull this.inlineComposer.composerContent))}}
          <div id="inline-editor-form">
            <Form
              @data={{hash content=this.inlineComposer.composerContent}}
              @onSubmit={{this.editPost}}
              @onRegisterApi={{this.registerAPI}}
              as |form|
            >
              <div id="inline-editor">
                <form.Field
                  @name="editReason"
                  @title={{i18n (themePrefix "composer_edit_reason_title")}}
                  @type="input"
                  {{on "keydown" this.handleKeyDown}}
                  as |field|
                >
                  <field.Control placeholder={{i18n "composer.edit_reason"}} />
                </form.Field>
                <br />
                <form.Field
                  @name="content"
                  @validation="required"
                  @title="Content"
                  @showTitle={{false}}
                  @type="composer"
                  @onSet={{this.onContentSet}}
                  {{on "keydown" this.handleKeyDown}}
                  as |field|
                >
                  <field.Control
                    @height={{this.height}}
                    @preview={{settings.show_preview}}
                  />
                </form.Field>
              </div>

              <div class="button-row">
                <form.Submit @icon="pencil" @label="composer.save_edit" />
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
                <DButton
                  @action={{this.inlineComposer.clearCache}}
                  class="btn-transparent"
                  @translatedLabel="Clear cache"
                />
              </div>
            </Form>
          </div>
        {{else}}
          <DConditionalLoadingSpinner @condition={{true}} />
        {{/if}}
      {{/if}}
    {{else}}
      {{yield}}
    {{/if}}
  </template>
}
