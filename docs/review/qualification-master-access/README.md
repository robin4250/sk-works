# 資格マスター権限候補

既存本番の owner/admin の ALL policy に加え、自社 manager の UPDATE/DELETE のみを許可する候補。INSERT権限は変更しない。既存の account_deletion_access_guard は維持する。DELETE は既存の worker_qualifications FK RESTRICT により利用中の資格を削除できない。過去の資格データの保持が目的。

本番未適用。社員、閲覧者、他社manager、本人の異動、資格保有中削除、既存 owner/admin、アカウントアクセス制限、削除前後の記録保持のNative PostgreSQL RLS・UI検証が必要。managerへのmaster編集画面のアクセスを別途用意する必要がある。
