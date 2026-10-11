# Milestone gallery

Store selected milestone verification images here for potential future public showcasing. Adding a capture does not authorize publishing a site or uploading to an external gallery.

The owner has rejected current captures for upload in their present state. Retain them as internal development evidence. Do not upload these images to external services, Library or campaign media. Improved future public imagery requires owner clearance through Coordinator.

Use a milestone subdirectory and descriptive lowercase filenames. Images and videos are tracked with Git LFS through the repository's `.gitattributes`; install Git LFS before adding media. Keep metadata in ordinary Markdown.

At milestone completion, assess any images sent in the implementation chat. Retain representative captures that clearly demonstrate completed behavior. Exclude secrets, personal data, misleading presentation and distracting debug clutter. Record the exact verified commit, capture route, verification scope, limitations, author and license alongside each selection. First-party captures must follow the project's MIT and third-party asset provenance rules. Do not imply graphical acceptance from headless test output.

For each selected capture, add a row to a milestone `README.md`:

| File | Verified commit | Capture route and demonstrated behavior | Limitations | Author / license / provenance |
| --- | --- | --- | --- | --- |

Before committing media, verify its Git attributes and inspect the staged blob to confirm it is an LFS pointer. Keep the original capture available until the LFS upload succeeds. If no suitable images were sent, record that in the milestone completion report; do not invent a screenshot.
