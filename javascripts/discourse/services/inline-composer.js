import { tracked } from "@glimmer/tracking";
import Service from "@ember/service";

export default class InlineComposerService extends Service {
  @tracked editingPostId = null;

  startEditing(postId) {
    this.editingPostId = postId;
  }

  stopEditing() {
    this.editingPostId = null;
  }

  get isEditing() {
    return this.editingPostId !== null;
  }
}
