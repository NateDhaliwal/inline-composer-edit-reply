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
import { eq, not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DConditionalLoadingSpinner from "discourse/ui-kit/d-conditional-loading-spinner";
import { isundefnull } from "../helpers/isundefnull";

export default class InlineComposer extends Component {
  @service inlineComposer;
  @service modal;

  @tracked formApi;

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
    set("content", value);
    this.scheduleDraftSave(value);
  }

  scheduleDraftSave() {
    this._saveDraftDebounce = debounce(this, this.performDraftSave, 1000);
  }

  @action
  performDraftSave() {
    if (this.inlineComposer.editingPostId !== this.args.post.id) {
      return;
    }
    const value = this.formApi?.get("content");
    if (value !== undefined) {
      this.inlineComposer.saveDraft(value, this.args.post, false);
    }
  }

  @action
  cancelComposer() {
    cancel(this._saveDraftDebounce);

    return new Promise((resolve) => {
      if (
        this.formApi?.isDirty ||
        this.inlineComposer.composerContent !== this.formApi?.get("content")
      ) {
        this.modal.show(DiscardDraftModal, {
          model: {
            confirmMessageKey: "post.cancel_composer.confirm_edit",
            discardButtonKey: "post.cancel_composer.discard_edit",
            onDestroyDraft: async () => {
              await this.inlineComposer.clearDraft(this.args.post.id);
              this.inlineComposer.stopEditing(this.formApi.get("content"), {
                clearCache: true,
              });
              resolve(true);
            },
            onCancelDiscard: () => {
              resolve(false);
            },
          },
        });
      } else {
        this.inlineComposer.stopEditing(this.formApi.get("content"));
        resolve();
      }
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
        this.inlineComposer.stopEditing(this.formApi.get("content"));
      }
    }
  }

  <template>
    {{#if (eq this.inlineComposer.editingPostId @post.id)}}
      {{#if this.inlineComposer.loading}}
        <DConditionalLoadingSpinner
          @condition={{this.inlineComposer.loading}}
        />
      {{else}}
        {{log this.inlineComposer.composerContent}}
        {{#if (not (isundefnull this.inlineComposer.composerContent))}}
          <Form
            @data={{hash content=this.inlineComposer.composerContent}}
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
          <p>Error!!</p>
        {{/if}}
      {{/if}}
    {{else}}
      {{yield}}
    {{/if}}
  </template>
}
