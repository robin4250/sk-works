# Personal history follow-up — isolated only

Depends on manager UI PR 1720 and the reviewed OCR PR 1716. Not for the next iPhone Release; deployable:false. Backend 1719 remains frozen at 77dc; payroll document-reader and legacy rollout contracts remain unresolved. No backend, financial reader or production changes occur here.

The personal page starts from OCR893c226542ac13ef105ad24085ac375fa66e7a1e's exact blob bf8052976f290205137730eb4e4e9b0fe04fbab7. Only manager-deletion edit/withdrawal guards are added. Its parser, OCR tests and workflow are included as unchanged source dependencies, not a second OCR implementation. Root must integrate OCR first and preserve those blob identities.

Personal history accepts manager_deleted only as a strict optional boolean and keeps original approval/withdrawn values. A manager-deleted original is displayed as retained history and cannot start applicant edit/withdrawal. The personal-change command constructor independently rejects it. Old submitted documents, receipt objects and originals are untouched.

The source tests cover manager-deleted and ordinary originals; real Auth, Storage, device and shared accounting correctness remain unproven. Until the full dependency and rollout contract is complete, this source must not be described as production deletion support.
