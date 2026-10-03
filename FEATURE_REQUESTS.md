# PDFMate 0.4.0 — workbook requests

Source: the ten Feature Request entries for PDFMate in App Ideas.xlsx.

| Request | Change | Validation |
| --- | --- | --- |
| More languages and detection | Named supported languages share ML Kit's five script models; automatic mode samples first/middle/last pages. Recognized language codes appear in page preview where available. | Script scoring, manual overrides and OCR regression suite. |
| OLED / glass theme | True black dark scaffold, rounded controls and bounded frosted tool cards. Uses existing System/Light/Dark preference. | Theme contrast regression and Android app smoke. |
| Auto scan timing / retry | At least 12 stable detections and 1.4 seconds of hold; gaps and motion reset it; capture/cancel re-arms. | Deterministic timing and re-arm regressions. |
| Crop picture-in-picture | Corner-focused zoom while dragging, placed on the opposite side. Decode capped at 1600px for preview. | Drag-offset regression; camera QA still requires phones. |
| Crop accuracy | Strict still detection; invalid quadrilaterals rejected; Detect again and Full photo corrections available. | Existing polygon/error tests; real-paper accuracy needs physical QA. |
| HD scans | Camera veryHigh preset, crop up to 4096px and JPEG quality 96, no artificial upscaling. | Camera initialization/lifecycle smoke; achieved resolution depends on camera. |
| Text copy from preview | Viewer action opens current page with OCR line boxes; tap visible text to select/copy or copy the page. Zoom, model override, page navigation, Cancel and Retry. | Preview selection/copy widget regression. |
| Screenshot aspect ratio | Per-image PDF page dimensions preserve original ratio, encoded one image at a time in an isolate; native file-backed merge and rollback cleanup. | Android tall/wide aspect ratio and invalid second-image cleanup test. |
| Page-number split | Scrollable lazy page checkbox grid, selected pages become one PDF in source order; existing custom groups retained. | Checkbox selection and zero-based output regression. |
| Saved signatures | Named PNGs in private app storage; atomic publication, reload, reuse and delete. Interrupted files removed on list load. | Unicode names, malformed records, process-reload and deletion regression. |

Automatic OCR chooses a dominant script, not per-page mixed-script recognition. Arabic/Hebrew remain unsupported by the installed recognizer. Exact language metadata may be absent. An empty sample asks for a manual choice.

Physical Samsung/Xiaomi/Pixel/OnePlus camera and touch QA is not replaced by emulator results. Production account setup and signing are separate release requirements. The previous R8/WorkDatabase release-startup guard remains enabled.
