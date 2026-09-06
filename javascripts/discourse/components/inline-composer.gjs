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
import { and, eq, not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import { DConditionalLoadingSpinner } from "discourse/ui-kit/d-conditional-loading-spinner";
import { isundefnull } from "../helpers/is-undefined-or-null";

export default class InlineComposer extends Component {
  @service inlineComposer;
  @service modal;

  @tracked formApi;

  constructor() {
    super(...arguments);
  }

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
      this.inlineComposer.stopEditing(this.formApi.get("content"));
      await this.inlineComposer.clearDraft(this.args.post.id);
      // this.inlineComposer.composerContent = newContent; // We update the composer to the new value
    } catch (e) {
      popupAjaxError(e);
    }
  }

  // Form API
  @action
  registerAPI(api) {
    // await this.getRawPost();
    this.formApi = api;
  }

  @action
  onContentSet(value, { set }) {
    set("content", value);
    this.scheduleDraftSave(value);
  }

  scheduleDraftSave(value) {
    this._saveDraftDebounce = debounce(
      this,
      this.inlineComposer.saveDraft,
      value,
      this.args.post,
      1000
    );
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
      }
    });
  }

  @action
  async saveDraftForm() {
    const value = this.formApi?.get("content");
    if (value !== undefined) {
      await this.inlineComposer.saveDraft(value, this.args.post, true);
      this.inlineComposer.stopEditing(this.formApi.get("content"));
    }
  }

  <template>
    {{#if (eq this.inlineComposer.editingPostId @post.id)}}
      {{#if this.inlineComposer.loading}}
        <DConditionalLoadingSpinner
          @condition={{this.inlineComposer.loading}}
        />
      {{else}}
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
      {{/if}}
    {{else}}
      {{yield}}
    {{/if}}
  </template>
}
