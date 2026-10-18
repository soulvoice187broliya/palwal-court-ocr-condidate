# Palwal Court OCR Scanner verification status

## Fixed before build
- Removed hardcoded 18/10/2026 next-hearing default. Missing dates now remain blank.
- Removed “issue date = receipt date” fallback. Missing issue dates remain blank.
- Removed arbitrary last-date fallback for next hearing: the last date on a warrant can be the return-by deadline, not the court hearing. Parser now prioritizes labeled NEXT DATE and explicit summons appearance-date wording.
- Added date normalization and validation; invalid dates are rejected.
- Added order-type recognition for common OCR variants such as “Non-Ballable Warrant”.
- Added Flutter unit tests for date normalization and month/year helpers.
- Added an Android emulator install/launch step to GitHub Actions.

## Workbook finding
The supplied GH.xlsx has Sheet1 plus Sheet2 and Sheet3. The active header row contains 54 columns through BB, with an empty AO-equivalent (zero-based column 41 / Excel AP) gap; `BC` is a new column. Existing workbook header validation matches many legacy spellings, but Column F/G/H meanings should still be compared with the user's desired schema before routine production use. No original records or sheets should be deleted.

## Sample validation benchmark
`tests/ocr_benchmark.csv` records five manually inspected images. Three are Palwal warrants. Two are Bhiwani summons and are negative geography controls (Palwal-specific logic must not mislabel them Palwal). Ground-truth next hearing dates come from the printed `NEXT DATE` label; issue dates come from the bottom issue-date wording. The included Tesseract OCR output is a reference only. These tests do **not** establish Google Cloud Vision production accuracy because the configured Cloud Vision endpoint is not available in this build environment and the app's parser has not yet been exercised with its own runtime.

## APK verification
A full release build and emulator smoke test must complete successfully in GitHub Actions. The current local environment does not include Flutter/Dart or Android SDK tools, so a release APK cannot honestly be claimed from local testing. CI is configured to compile, test, verify the APK file exists, install it in an emulator, and start the package before upload.

## Live eCourts updates
The public eCourts CNR search shows a CAPTCHA. Do not automate CAPTCHA solving. Auto-update remains disabled until an authorized data feed or staff-verified court-status export is configured.
