import { apiInitializer } from "discourse/lib/api";
import InlineComposer from "../components/inline-composer";
import InlineComposerEditButton from "../components/inline-composer-edit-button";

export default apiInitializer((api) => {
  const siteSettings = api.container.lookup("service:site-settings");
  const inlineComposer = api.container.lookup("service:inline-composer");
  api.modifyClass("route:topic.from-params", (Superclass) => {
    return class extends Superclass {
      setupController(controller, params) {
        const topic = params._nested?.topic || this.modelFor("topic"); // For nested topics as well

        if (topic?.draft) {
          let draftData;
          try {
            draftData = JSON.parse(topic.draft);
          } catch {
            draftData = null;
          }

          if (draftData?.action === "edit" && draftData?.postId) {
            if (params._nested?.topic) {
              params._nested.topic.draft = null;
            }

            inlineComposer.startEditing(draftData.postId);
          }
        }

        super.setupController(...arguments);
      }
    };
  });

  api.registerValueTransformer(
    "post-menu-buttons",
    ({ value: dag, context: { post, buttonKeys, state } }) => {
      if (post.canEdit) {
        dag.add("inline-composer", InlineComposerEditButton, {
          post,
          after: post.wiki
            ? buttonKeys.SHOW_MORE
            : buttonKeys[
                buttonKeyBefore(siteSettings, buttonKeys, state.collapsed)
              ],
        });
        dag.delete(buttonKeys.EDIT);
      }
    }
  );

  api.renderInOutlet("post-content-cooked-html", InlineComposer);
});

function buttonKeyBefore(siteSettings, buttonKeys, collapsed) {
  const postMenu = siteSettings.post_menu.split("|");
  const hiddenItems = siteSettings.post_menu_hidden_items.split("|");
  const beforeName = postMenu[postMenu.indexOf("edit") - 1];

  for (let key in buttonKeys) {
    if (buttonKeys[key] === beforeName) {
      if (!collapsed) {
        return key;
      }

      if (!hiddenItems.includes(beforeName)) {
        return key;
      } else {
        return "COPY_LINK";
      }
    }
  }
}
