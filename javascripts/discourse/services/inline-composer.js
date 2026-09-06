import { tracked } from "@glimmer/tracking";
import { cancel } from "@ember/runloop";
import Service, { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import Draft from "discourse/models/draft";
import { i18n } from "discourse-i18n";

export default class InlineComposerService extends Service {
  @service messageBus;
  @service toasts;
  @service dialog;

  @tracked editingPostId = null;
  @tracked composerContent = undefined;
  @tracked currentSequence = 0;
  @tracked loading = true;
  @tracked draftForceSave = false;
  #cache = {};

  draftKeyFor(postId) {
    return `post_${postId}`;
  }

  async startEditing(postId) {
    // Reset all!
    this.editingPostId = postId;
    this.composerContent = undefined;
    this.currentSequence = 0;
    this.loading = true;
    this.draftForceSave = false;

    if (postId in this.#cache) {
      const cachedEntry = this.#cache[postId];
      this.composerContent = cachedEntry.content;
      this.currentSequence = cachedEntry.draft_sequence;
    } else {
      await this.loadDraft(postId);
    }
    this.loading = false;
  }

  stopEditing(value, { clearCache = false }) {
    if (clearCache) {
      delete this.#cache[this.editingPostId];
    } else if (value !== undefined) {
      this.#cache[this.editingPostId] = {
        content: value,
        draft_sequence: this.currentSequence,
      };
    }
    this.editingPostId = null;
  }

  get isEditing() {
    return this.editingPostId !== null;
  }

  get draftKey() {
    return `post_${this.editingPostId}`;
  }

  async loadDraft(postId) {
    try {
      const draft = await Draft.get(this.draftKey);
      this.currentSequence = draft.draft_sequence;
      const composer_content = draft.draft
        ? JSON.parse(draft.draft).reply
        : null;
      this.composerContent = composer_content;
      this.#cache[postId] = {
        content: composer_content,
        draft_sequence: draft.draft_sequence,
      };
    } catch (e) {
      // If the post is not in the cache or in the user's drafts, fetch the post
      if (e.status === 404) {
        try {
          const res = await ajax(`/posts/${postId}.json`);
          this.composerContent = res.raw;
          this.#cache[postId] = {
            content: res.raw,
            draft_sequence: 0,
          };
          this.loading = false;
        } catch (e2) {
          this.loading = false;
          popupAjaxError(e2);
        }
      }
      if (e.status === 0) {
        // Network error
        this.composerContent = undefined;
        popupAjaxError(e);
        this.loading = false;
      }
    }
  }

  async clearDraft(postId) {
    const draftEntry = this.#cache[postId]; // Anything to reduce calls
    if (!draftEntry) {
      return;
    }
    await Draft.clear(this.draftKeyFor(postId), draftEntry.draft_sequence);
    delete this.#cache[postId];
  }

  async saveDraft(value, post, showToast = false) {
    if (this.editingPostId !== post.id) {
      return;
    }
    this.currentSequence += 1;
    const data = {
      reply: value,
      action: "edit_post",
      original_title: post.topic.title,
      original_text: this.composerContent,
      postId: post.id,
      categoryId: post.topic.category_id,
      tags: post.topic.tags,
      archetype: "regular",
      slug: post.topic.slug,
      topicId: post.topic_id,
    };
    try {
      await Draft.save(
        this.draftKey,
        this.currentSequence,
        data,
        this.messageBus.clientId,
        { forceSave: this.draftForceSave }
      );
      this.#cache[post.id] = {
        content: value,
        draft_sequence: this.currentSequence,
      };

      if (showToast) {
        // The user clicked the 'Save Draft' button
        this.toasts.success({
          duration: "short",
          data: {
            message: i18n("composer.draft_saved"),
          },
        });
      }
    } catch (e) {
      const xhr = e && e.jqXHR;

      // Edit conflict!
      if (
        xhr &&
        xhr.status === 409 &&
        xhr.responseJSON &&
        xhr.responseJSON.errors &&
        xhr.responseJSON.errors.length
      ) {
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
                  this.saveDraft(value, post, showToast); // Force retry
                },
              },
            ],
          });
          return;
        }
      }
    }
  }
}
