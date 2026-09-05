import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import Form from "discourse/components/form";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

export default class InlineComposer extends Component {
  @service inlineComposer;

  @tracked rawPost;

  constructor() {
    super(...arguments);
    this.getRawPost();
  }

  async getRawPost() {
    try {
      const res = await ajax(`/posts/${this.args.post.id}.json`);
      this.rawPost = res.raw;
    } catch (e) {
      popupAjaxError(e);
    }
  }

  @action
  async handleSubmit(data) {
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
      await this.getRawPost();
    } catch (e) {
      popupAjaxError(e);
    }
  }

  <template>
    {{#if (eq this.inlineComposer.editingPostId @post.id)}}
      <Form
        @data={{hash content=this.rawPost}}
        @onSubmit={{this.handleSubmit}}
        as |form|
      >
        <form.Field
          @name="content"
          @validation="required"
          @title="&nbsp;"
          @type="composer"
          as |field|
        >
          <field.Control @preview={{settings.show_preview}} />
        </form.Field>

        <form.Submit @label={{i18n (themePrefix "composer_edit_text")}} />
      </Form>
    {{else}}
      {{yield}}
    {{/if}}
  </template>
}
