import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/ui-kit/d-button";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";

export default class InlineComposerEditButton extends Component {
  @service inlineComposer;

  @action
  async toggleComposer() {
    if (this.inlineComposer.isEditing) {
      // So that we can switch to editing another post effortlessly
      if (this.inlineComposer.editingPostId !== this.args.post.id) {
        this.inlineComposer.stopEditing(this.inlineComposer.editingPostId);
        await this.inlineComposer.startEditing(this.args.post.id);
      }
    } else {
      await this.inlineComposer.startEditing(this.args.post.id);
    }
  }

  <template>
    <DButton
      class={{dConcatClass
        "post-action-menu__edit"
        "edit"
        (if @post.wiki "create" "btn-flat")
      }}
      @action={{this.toggleComposer}}
      @ariaLabel="post.controls.edit"
      @icon={{if @post.wiki "far-pen-to-square" "pencil"}}
      @label={{if @post.wiki "post.controls.edit_action"}}
      @title="post.controls.edit"
    />
  </template>
}
