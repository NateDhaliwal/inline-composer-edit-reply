import { apiInitializer } from "discourse/lib/api";
import InlineComposer from "../components/inline-composer";
import InlineComposerEditButton from "../components/inline-composer-edit-button";

export default apiInitializer((api) => {
  api.registerValueTransformer(
    "post-menu-buttons",
    ({ value: dag, context: { post, buttonKeys } }) => {
      if (post.canEdit) {
        dag.add("inline-composer-editing", InlineComposerEditButton, {
          post,
          after: [buttonKeys.COPY_LINK],
          before: [buttonKeys.SHOW_MORE],
        });

        dag.delete(buttonKeys.EDIT);
      }
    }
  );
  api.renderInOutlet("post-content-cooked-html", InlineComposer);
});
