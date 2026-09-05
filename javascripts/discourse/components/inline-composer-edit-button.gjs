import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/ui-kit/d-button";

export default class InlineComposerEditButton extends Component {
  @service inlineComposer;

  @action
  toggleComposer() {
    if (this.inlineComposer.isEditing) {
      // So that we can switch to editing another post effortlessly
      if (this.inlineComposer.editingPostId !== this.args.post.id) {
        this.inlineComposer.stopEditing(this.inlineComposer.editingPostId);
        this.inlineComposer.startEditing(this.args.post.id);
      } else {
        this.inlineComposer.stopEditing(this.inlineComposer.editingPostId);
      }
    } else {
      this.inlineComposer.startEditing(this.args.post.id);
    }
  }

  <template>
    <DButton
      class="btn-icon btn-flat edit"
      @icon="pencil"
      @action={{this.toggleComposer}}
    />
  </template>
}
