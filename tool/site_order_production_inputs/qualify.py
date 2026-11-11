"""Offline order dependency inventory. No database, subprocess or network execution."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath

# Frozen source inventories; declared names are not a SQL parser or caller closure.
PINS = json.loads("{\"sql\":[{\"path\":\"docs/review/trade-documents-hub/master-and-standalone-context.sql.review-only\",\"commit\":\"6a24114471a9c264fad1aeec5dd2222915ddbedf\",\"sha256\":\"7796c2e7bcc7a9eca78f1b79ce8cfc87fcd978c1dc4a4ddb7a5a8ced17b597e5\",\"bytes\":19302,\"kind\":\"master-gate-C\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[\"public.current_master_feature_flags\",\"public.set_master_feature_enabled_with_proof\",\"private.require_trade_documents_master_feature\",\"private.require_standalone_trade_document_access\",\"public.standalone_trade_document_access\",\"private.standalone_trade_document_registration_context\",\"public.standalone_trade_document_registration_context\"]},{\"path\":\"docs/candidates/trade_document_bound_seal_consent_20261021.sql.review-only\",\"commit\":\"14cf77f4b166bcb86d0f5fef68080841ac89a27a\",\"sha256\":\"dce7ca9653988c642d49325ff331d0548448206ae3e8c2e2dc24202d36a04e01\",\"bytes\":23740,\"kind\":\"private-site-baseline\",\"declared_schemas\":[\"trade_document_consent_private\"],\"declared_tables\":[\"trade_document_consent_private.documents\",\"trade_document_consent_private.local_links\",\"trade_document_consent_private.revisions\",\"trade_document_consent_private.consents\",\"trade_document_consent_private.events\",\"trade_document_consent_private.receipts\"],\"declared_functions\":[\"trade_document_consent_private.immutable\",\"trade_document_consent_private.protect_content\",\"trade_document_consent_private.require_actor\",\"trade_document_consent_private.lock_pair\",\"trade_document_consent_private.parent_binding\",\"trade_document_consent_private.linked_view_allowed\",\"trade_document_consent_private.prepare_document\",\"trade_document_consent_private.bind_local\",\"trade_document_consent_private.require_local\",\"trade_document_consent_private.own_seal\",\"trade_document_consent_private.preview_own\",\"trade_document_consent_private.decide\",\"trade_document_consent_private.confirm_local_document\",\"trade_document_consent_private.binding_matches_approval\",\"trade_document_consent_private.render_approved\"],\"same_in_current_app_tree\":true},{\"path\":\"docs/review/site-order-artifact-registration/private-register.sql.review-only\",\"commit\":\"14cf77f4b166bcb86d0f5fef68080841ac89a27a\",\"sha256\":\"330ce27c0bbed24fbcfa60ae3f34201ee704d0b4fddd69fc76cd049c4c5119db\",\"bytes\":15205,\"kind\":\"private-site-baseline\",\"declared_schemas\":[\"site_order_artifact_private\"],\"declared_tables\":[\"site_order_artifact_private.render_jobs\",\"site_order_artifact_private.pdf_records\"],\"declared_functions\":[\"site_order_artifact_private.counterparty_context\",\"site_order_artifact_private.prepare_job\",\"site_order_artifact_private.register_canonical_pdf\"],\"same_in_current_app_tree\":true},{\"path\":\"docs/review/site-order-manager-purpose/adapter.sql.review-only\",\"commit\":\"14cf77f4b166bcb86d0f5fef68080841ac89a27a\",\"sha256\":\"b46c730079f47477e8c73e89b192867b34c833ea263ddc7f9d348d65add36960\",\"bytes\":16801,\"kind\":\"private-site-baseline\",\"declared_schemas\":[\"site_order_manager_private\"],\"declared_tables\":[\"site_order_manager_private.document_scopes\",\"site_order_manager_private.generated_sources\"],\"declared_functions\":[\"site_order_manager_private.counterparty_context\",\"site_order_manager_private.require_actor\",\"site_order_manager_private.prepare_site_document\"],\"same_in_current_app_tree\":false},{\"path\":\"docs/review/site-order-package-flow/foundation.sql.review-only\",\"commit\":\"14cf77f4b166bcb86d0f5fef68080841ac89a27a\",\"sha256\":\"3c0bc1489767e879c39d3dbf44b94b201d4296f0711233363e9c54de8849ab67\",\"bytes\":9794,\"kind\":\"private-site-baseline\",\"declared_schemas\":[\"site_order_package_private\"],\"declared_tables\":[\"site_order_package_private.packages\",\"site_order_package_private.notice_intents\"],\"declared_functions\":[\"site_order_package_private.send_order\"],\"same_in_current_app_tree\":false},{\"path\":\"docs/review/site-order-package-flow/legacy-response-guard.sql.review-only\",\"commit\":\"14cf77f4b166bcb86d0f5fef68080841ac89a27a\",\"sha256\":\"6cba3f988e2494261f404ad2cf4bc0c3816ccf88fb34bcfbcf9ea62cdae1bbae\",\"bytes\":2838,\"kind\":\"private-site-baseline\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[],\"same_in_current_app_tree\":true},{\"path\":\"docs/review/site-order-package-flow/approval.sql.review-only\",\"commit\":\"14cf77f4b166bcb86d0f5fef68080841ac89a27a\",\"sha256\":\"5e538255e740c4449512ffb83c04e682a5f5d4e7efe9ff15c56c8a098e912005\",\"bytes\":10859,\"kind\":\"private-site-baseline\",\"declared_schemas\":[],\"declared_tables\":[\"site_order_package_private.approvals\",\"site_order_package_private.reply_intents\",\"site_order_package_private.approval_notice_intents\"],\"declared_functions\":[\"site_order_package_private.approve_order\"],\"same_in_current_app_tree\":false},{\"path\":\"docs/review/site-order-package-flow/approval-consent.sql.review-only\",\"commit\":\"14cf77f4b166bcb86d0f5fef68080841ac89a27a\",\"sha256\":\"eb41d5f8dd426e11b40cbc5c3affa4a02ace009dd1bae756b97b155770fe31de\",\"bytes\":13124,\"kind\":\"private-site-baseline\",\"declared_schemas\":[],\"declared_tables\":[\"site_order_package_private.approval_previews\",\"site_order_package_private.ready_reply_jobs\"],\"declared_functions\":[\"site_order_package_private.preview_approval\",\"site_order_package_private.approve_with_consent\"],\"same_in_current_app_tree\":false},{\"path\":\"docs/review/site-order-package-flow/archive-read.sql.review-only\",\"commit\":\"14cf77f4b166bcb86d0f5fef68080841ac89a27a\",\"sha256\":\"6d2047dead2eb2c85efdf7a9bd49513b482ff373309807fca2dc23b786848e9f\",\"bytes\":3850,\"kind\":\"private-site-baseline\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[\"site_order_package_private.read_actor\",\"site_order_package_private.package_status\",\"site_order_package_private.archive_original\"],\"same_in_current_app_tree\":true},{\"path\":\"docs/review/site-order-package-flow/delivery.sql.review-only\",\"commit\":\"14cf77f4b166bcb86d0f5fef68080841ac89a27a\",\"sha256\":\"7f5c1e708c3144693547038e7e581c492f81dc16c18a9cb6c176007018a8e295\",\"bytes\":15430,\"kind\":\"private-site-baseline\",\"declared_schemas\":[],\"declared_tables\":[\"site_order_package_private.acceptance_deliveries\",\"site_order_package_private.notification_receipts\"],\"declared_functions\":[\"site_order_package_private.ready_reply\",\"site_order_package_private.deliver_acceptance\",\"site_order_package_private.dispatch_notifications\",\"site_order_package_private.delivery_status\"],\"same_in_current_app_tree\":false},{\"path\":\"docs/review/site-order-package-flow/read-surfaces.sql.review-only\",\"commit\":\"14cf77f4b166bcb86d0f5fef68080841ac89a27a\",\"sha256\":\"d411e79f8aa7379f0c0aefa1a6667994731b7adbe4c5d1da5e91bcdb752d975f\",\"bytes\":4275,\"kind\":\"private-site-baseline\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[\"site_order_package_private.package_detail\",\"site_order_package_private.package_list\",\"site_order_package_private.recipient_targets\"],\"same_in_current_app_tree\":true},{\"path\":\"docs/review/site-order-package-flow/archive-payload.sql.review-only\",\"commit\":\"14cf77f4b166bcb86d0f5fef68080841ac89a27a\",\"sha256\":\"596ec400fe26aeee592ecd168474974d05a3ff5c23c97011e6f8e6e0c8e4262f\",\"bytes\":3649,\"kind\":\"private-site-baseline\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[\"site_order_package_private.archive_payload\",\"site_order_package_private.history_entries\"],\"same_in_current_app_tree\":true},{\"path\":\"docs/review/site-order-package-flow/approval-operation.sql.review-only\",\"commit\":\"14cf77f4b166bcb86d0f5fef68080841ac89a27a\",\"sha256\":\"1a1552dd162c8081612609d7dc8b52c0829a243581e805dc623fd652d4bd4352\",\"bytes\":7639,\"kind\":\"private-site-baseline\",\"declared_schemas\":[],\"declared_tables\":[\"site_order_package_private.approval_operations\"],\"declared_functions\":[\"site_order_package_private.approve_operation\",\"site_order_package_private.reconcile_approval\"],\"same_in_current_app_tree\":true},{\"path\":\"docs/review/site-order-package-flow/refusal.sql.review-only\",\"commit\":\"14cf77f4b166bcb86d0f5fef68080841ac89a27a\",\"sha256\":\"bb1d84441475ee8d5a87eb84e7fd1401489ab44258ba30d354d47693c20414be\",\"bytes\":12722,\"kind\":\"private-site-baseline\",\"declared_schemas\":[],\"declared_tables\":[\"site_order_package_private.refusals\",\"site_order_package_private.refusal_operations\",\"site_order_package_private.refusal_notice_receipts\"],\"declared_functions\":[\"site_order_package_private.refuse_order\",\"site_order_package_private.reconcile_refusal\",\"site_order_package_private.dispatch_refusal_notifications\",\"site_order_package_private.package_decision_detail\"],\"same_in_current_app_tree\":false},{\"path\":\"docs/candidates/trade_document_confirmation_api_20261022.sql.review-only\",\"commit\":\"14cf77f4b166bcb86d0f5fef68080841ac89a27a\",\"kind\":\"extract-one-private-actor-only\",\"source_sha256\":\"18d738705b4f55a82e67faec31f115473df38c5a51bcb31da6e621c10646db83\",\"statement_sha256\":\"0da8df5dd78bdd44daa9757da346a48e4e7cbb63bada0b65f849cc060d2e3b15\",\"declared_functions\":[\"trade_document_confirmation_api_private.actor\"],\"financial_public_rpc_installation\":false},{\"path\":\"docs/review/site-order-package-flow/reply-recovery.sql.review-only\",\"commit\":\"de4d4bb018e8c8ca56b0c85bde09fadebca312a4\",\"sha256\":\"991281df5f789e1e6a3d469dd854609a065d2a6d56db33b85a08d3cf57fd9979\",\"bytes\":20229,\"kind\":\"private-site-extension\",\"declared_schemas\":[],\"declared_tables\":[\"site_order_package_private.reply_recovery_previews\",\"site_order_package_private.reply_recovery_leases\",\"site_order_package_private.reply_recovery_operations\",\"site_order_package_private.reply_recovery_cancellations\"],\"declared_functions\":[\"site_order_package_private.reply_recovery_target\",\"site_order_package_private.preview_reply_recovery\",\"site_order_package_private.confirm_reply_recovery\",\"site_order_package_private.require_reply_recovery_lease\",\"site_order_package_private.reconcile_reply_recovery\",\"site_order_package_private.ready_recovered_reply\",\"site_order_package_private.reply_recovery_status\"]},{\"path\":\"docs/review/site-order-package-flow/site-history.sql.review-only\",\"commit\":\"f4c6da47e8c6bd894c920ab1d85399a4dc5da7bb\",\"sha256\":\"0f9cc2f094e8146089a8cdf89f10fb0244ce5d80da239497b76d5c602285e577\",\"bytes\":2842,\"kind\":\"private-site-extension\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[\"site_order_package_private.site_history_entries\"]},{\"path\":\"docs/review/site-order-outgoing/source-and-prepare-observation.sql.review-only\",\"commit\":\"05af8016f4b5d5df94604eac48fae85c1a25cd9b\",\"sha256\":\"91c6e846a2aec0923ab443820d714524f31cf315008fc83aaa9c5fe18d06ca2f\",\"bytes\":10907,\"kind\":\"outgoing-private-purpose\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[\"site_order_manager_private.outgoing_context\",\"site_order_manager_private.observe_prepare\"]},{\"path\":\"docs/review/site-order-outgoing/prepare-operation.sql.review-only\",\"commit\":\"05af8016f4b5d5df94604eac48fae85c1a25cd9b\",\"sha256\":\"d710f89b8e14900329a78e417cc2dfe0484f4b62ec45627adc7951b3ef4553b7\",\"bytes\":24066,\"kind\":\"outgoing-private-purpose\",\"declared_schemas\":[\"site_order_outgoing_private\"],\"declared_tables\":[\"site_order_outgoing_private.prepared_operations\",\"site_order_outgoing_private.prepare_retirements\"],\"declared_functions\":[\"site_order_outgoing_private.lock_key\",\"site_order_outgoing_private.source_hash\",\"site_order_outgoing_private.prepared_receipt\",\"site_order_outgoing_private.retired_receipt\",\"site_order_outgoing_private.phase\",\"site_order_outgoing_private.require_unsigned_prepare\",\"site_order_outgoing_private.prepare_order\",\"site_order_outgoing_private.operation_status\",\"site_order_outgoing_private.retire_prepare\"]},{\"path\":\"docs/review/site-order-outgoing/registered-targets.sql.review-only\",\"commit\":\"05af8016f4b5d5df94604eac48fae85c1a25cd9b\",\"sha256\":\"2ffdbde112c9a83c5327321d7a8ffdbbc9d95733ee35823522d94b5f43e61883\",\"bytes\":5374,\"kind\":\"outgoing-private-purpose\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[\"site_order_outgoing_private.registered_targets\"]},{\"path\":\"docs/review/site-order-outgoing-consent/coordinator.sql.review-only\",\"commit\":\"05af8016f4b5d5df94604eac48fae85c1a25cd9b\",\"sha256\":\"80d68722b289d5fc1b359dd7aa43b77329c648411f004410417e4ed2d6132ae9\",\"bytes\":20809,\"kind\":\"outgoing-private-purpose\",\"declared_schemas\":[],\"declared_tables\":[\"site_order_outgoing_private.preview_receipts\",\"site_order_outgoing_private.decision_receipts\"],\"declared_functions\":[\"site_order_outgoing_private.preview_unsigned\",\"site_order_outgoing_private.decision_result\",\"site_order_outgoing_private.confirm_unsigned\",\"site_order_outgoing_private.decision_status\"]},{\"path\":\"docs/review/site-order-compatibility/consumer-boundary.sql.review-only\",\"commit\":\"241a393077cc29b00c8e44b3518ab7a7fc050a91\",\"sha256\":\"81a4458d6106e3a128badaab8659165b10c37b6d8e63f16f4e95508db398d836\",\"kind\":\"superseding-existing-consumer-compatibility\"}],\"edge\":{\"sources\":[{\"path\":\"supabase/functions/site-order-workflow/index.ts\",\"commit\":\"05af8016f4b5d5df94604eac48fae85c1a25cd9b\",\"sha256\":\"6ab4143498d67da1224313452524031bf058482494193139d089687f45da622e\",\"bytes\":84,\"kind\":\"fixed-edge-source\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[]},{\"path\":\"supabase/functions/site-order-workflow/runtime.mjs\",\"commit\":\"05af8016f4b5d5df94604eac48fae85c1a25cd9b\",\"sha256\":\"b8c23fc662f1b6698c72d3a2baac17e62e7e7864a0654babe6db7afdb0cf28fe\",\"bytes\":2122,\"kind\":\"fixed-edge-source\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[]},{\"path\":\"supabase/functions/site-order-workflow/auth.mjs\",\"commit\":\"05af8016f4b5d5df94604eac48fae85c1a25cd9b\",\"sha256\":\"b71378004e878b785836acf6fdc9f616b875e36602d506e91cd1c8b0a4a1f6a8\",\"bytes\":1053,\"kind\":\"fixed-edge-source\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[]},{\"path\":\"supabase/functions/site-order-workflow/handler.mjs\",\"commit\":\"05af8016f4b5d5df94604eac48fae85c1a25cd9b\",\"sha256\":\"b168d769f1f1ca68839bc5145195f24673a606aee799621a327679a16453a594\",\"bytes\":8480,\"kind\":\"fixed-edge-source\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[]},{\"path\":\"supabase/functions/site-order-workflow/outgoing-handler.mjs\",\"commit\":\"05af8016f4b5d5df94604eac48fae85c1a25cd9b\",\"sha256\":\"528b134029733ad0573498b147566be2c2c811646904999c743e8e34688d03fc\",\"bytes\":6356,\"kind\":\"fixed-edge-source\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[]},{\"path\":\"supabase/functions/site-order-workflow/router.mjs\",\"commit\":\"05af8016f4b5d5df94604eac48fae85c1a25cd9b\",\"sha256\":\"12c4cb3f8748728ae1085ad0559ffd0c78b00f7c745e02468053261a08ec3bcb\",\"bytes\":676,\"kind\":\"fixed-edge-source\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[]},{\"path\":\"tool/site_order_canonical_core.mjs\",\"commit\":\"05af8016f4b5d5df94604eac48fae85c1a25cd9b\",\"sha256\":\"5c0c8e94e2abad1eabc2cf4aaed5a97612b815bef4790d7c9ffcad2f98eab7ca\",\"bytes\":9436,\"kind\":\"fixed-edge-source\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[]},{\"path\":\"tool/site_order_outgoing_execution_contract.mjs\",\"commit\":\"05af8016f4b5d5df94604eac48fae85c1a25cd9b\",\"sha256\":\"5f658a89fed4362032cc3a2d3604a32eb768e280fe25f4e687ab248fb0c56b4b\",\"bytes\":5123,\"kind\":\"fixed-edge-source\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[]},{\"path\":\"tool/site_order_outgoing_delivery_core.mjs\",\"commit\":\"05af8016f4b5d5df94604eac48fae85c1a25cd9b\",\"sha256\":\"510041111f2a21cbd9f2d22abd93853636fdc832bfe747f74d3c6bb17516e64a\",\"bytes\":8246,\"kind\":\"fixed-edge-source\",\"declared_schemas\":[],\"declared_tables\":[],\"declared_functions\":[]}],\"renderer_tool_commit\":\"bb3ff2cb5ff19408ca1aa7d49e4b0f5d215e9d5d\",\"renderer_files\":{\"build.py\":{\"sha256\":\"3373b431b617ea70cbb2c3b0842ee00795000cc8791e0026b6437e940979a022\",\"bytes\":4164},\"source_manifest.json\":{\"sha256\":\"4c4d4a61b6323a3c5e91f16dcdca6eccf4d9b8d59160ff4ad2adb72e2dd46d5b\",\"bytes\":6331},\"runtime-pins.json\":{\"sha256\":\"399f9a0324a0ff68f304cde880419e15bc47dc15986fc83a0200ae25e2d66ef6\",\"bytes\":686},\"build-proof.json\":{\"sha256\":\"740802e0e88fa8a6d44b50d8fb4459586549b0b7d2166f3d27f44ac2f6fd6631\",\"bytes\":912},\"runtime.mjs.in\":{\"sha256\":\"54ae3e21ee3a063e9b84e555fedec04f24b16a3c43540538fdd09afade6f5a74\",\"bytes\":1395},\"edge_adapter.mjs.in\":{\"sha256\":\"783a7e5367d4303c6956f839845453bfe99bb27095f088ea679a32767f2b3a86\",\"bytes\":704},\"edge_entry.dart.template\":{\"sha256\":\"85490124675e76fbf681de96ac83686dfd7fac38be4a7e6239b4f3cfa663ac48\",\"bytes\":2290},\"combined-deno.lock\":{\"sha256\":\"bd66f49049ae68e6a173c71a74e0ac21a943f2f4cb81130bee5568bf413f587f\",\"bytes\":7597}},\"original_renderer_source_commit\":\"65eb8fcec6af422c6a78269c273ec900db1d0d42\",\"renderer_sources_verified\":25,\"renderer_assets\":6,\"renderer_source_drift\":[],\"expected_outputs\":{\"main.mjs\":{\"bytes\":12802,\"sha256\":\"0599364b1dfc59e2063cf2a7bf83e0c46c6e03b20d0a4296de6405e8e6755c93\"},\"main.support.js\":{\"bytes\":200,\"sha256\":\"9b329fbb5f775a8c37a85ede978db00aa0e9543edbadb520c2f1fb0aac403140\"},\"main.wasm\":{\"bytes\":14332197,\"sha256\":\"eb8b1da6adb2804df16a5e078338cf3effdceb27d365bdc724d7cfd13e5b8359\"},\"runtime.mjs\":{\"bytes\":1446,\"sha256\":\"188e09cacbf51947a4952e3d6e94fd624d1c331eda46bfdf2b8298ba6a0be1a7\"}},\"old_five_file_workflow_pin_reusable\":false,\"complete_cli_bundle_measured\":false,\"deployed\":false},\"relations\":[\"auth.sessions\",\"auth.users\",\"private.account_deletion_access_restrictions\",\"private.company_connections\",\"private.company_seal_png_selection\",\"private.company_seal_png_versions\",\"public.companies\",\"public.company_members\",\"public.trade_companies\",\"private.master_feature_settings\",\"private.document_deliveries\",\"private.company_data_delivery_items\",\"private.site_share_inbox\",\"public.sites\",\"public.app_notifications\"],\"protected\":[{\"signature\":\"auth.jwt()\",\"source_md5\":\"2db09c3fc855ba90e71d3ae28cfadae3\",\"security_definer\":false,\"volatility\":\"s\",\"config\":null,\"owner\":\"supabase_auth_admin\",\"acl\":[{\"grantee\":\"PUBLIC\",\"grantor\":\"supabase_auth_admin\",\"privilege\":\"EXECUTE\",\"grant_option\":false},{\"grantee\":\"postgres\",\"grantor\":\"supabase_auth_admin\",\"privilege\":\"EXECUTE\",\"grant_option\":false},{\"grantee\":\"supabase_auth_admin\",\"grantor\":\"supabase_auth_admin\",\"privilege\":\"EXECUTE\",\"grant_option\":false},{\"grantee\":\"dashboard_user\",\"grantor\":\"supabase_auth_admin\",\"privilege\":\"EXECUTE\",\"grant_option\":false}]},{\"signature\":\"auth.uid()\",\"source_md5\":\"cdef18c69c4f4cbbced2eaf81e628b49\",\"security_definer\":false,\"volatility\":\"s\",\"config\":null,\"owner\":\"supabase_auth_admin\",\"acl\":[{\"grantee\":\"PUBLIC\",\"grantor\":\"supabase_auth_admin\",\"privilege\":\"EXECUTE\",\"grant_option\":false},{\"grantee\":\"supabase_auth_admin\",\"grantor\":\"supabase_auth_admin\",\"privilege\":\"EXECUTE\",\"grant_option\":false},{\"grantee\":\"dashboard_user\",\"grantor\":\"supabase_auth_admin\",\"privilege\":\"EXECUTE\",\"grant_option\":false}]},{\"signature\":\"private.account_access_allowed()\",\"source_md5\":\"aeca25db212c043c472334026bd98724\",\"security_definer\":true,\"volatility\":\"s\",\"config\":[\"search_path=\\\"\\\"\"],\"owner\":\"postgres\",\"acl\":[{\"grantee\":\"postgres\",\"grantor\":\"postgres\",\"privilege\":\"EXECUTE\",\"grant_option\":false},{\"grantee\":\"anon\",\"grantor\":\"postgres\",\"privilege\":\"EXECUTE\",\"grant_option\":false},{\"grantee\":\"authenticated\",\"grantor\":\"postgres\",\"privilege\":\"EXECUTE\",\"grant_option\":false},{\"grantee\":\"service_role\",\"grantor\":\"postgres\",\"privilege\":\"EXECUTE\",\"grant_option\":false}]},{\"signature\":\"private.document_company_seal_snapshot(jsonb,uuid,boolean)\",\"source_md5\":\"823cc52d0c652e7f04ff816a8a8eaf64\",\"security_definer\":true,\"volatility\":\"v\",\"config\":[\"search_path=\\\"\\\"\"],\"owner\":\"postgres\",\"acl\":[{\"grantee\":\"postgres\",\"grantor\":\"postgres\",\"privilege\":\"EXECUTE\",\"grant_option\":false}]},{\"signature\":\"private.require_reauthentication_session()\",\"source_md5\":\"b5c8e2f259a99b3c69694ad0640080e5\",\"security_definer\":true,\"volatility\":\"v\",\"config\":[\"search_path=\\\"\\\"\"],\"owner\":\"postgres\",\"acl\":[{\"grantee\":\"postgres\",\"grantor\":\"postgres\",\"privilege\":\"EXECUTE\",\"grant_option\":false}]},{\"signature\":\"private.account_deletion_barrier_key(uuid)\",\"source_md5\":\"84db8dfee728dd9187f3c05b29e29e1a\",\"security_definer\":false,\"volatility\":\"i\",\"config\":[\"search_path=\\\"\\\"\"],\"owner\":\"postgres\",\"acl\":[{\"grantee\":\"postgres\",\"grantor\":\"postgres\",\"privilege\":\"EXECUTE\",\"grant_option\":false},{\"grantee\":\"authenticated\",\"grantor\":\"postgres\",\"privilege\":\"EXECUTE\",\"grant_option\":false},{\"grantee\":\"service_role\",\"grantor\":\"postgres\",\"privilege\":\"EXECUTE\",\"grant_option\":false}]},{\"signature\":\"private.aoyagi_reisho_name_supported(text)\",\"source_md5\":\"ca6eecc48cfcbb24faac27c82bc3ed30\",\"security_definer\":false,\"volatility\":\"i\",\"config\":[\"search_path=\\\"\\\"\"],\"owner\":\"postgres\",\"acl\":[{\"grantee\":\"postgres\",\"grantor\":\"postgres\",\"privilege\":\"EXECUTE\",\"grant_option\":false}]},{\"signature\":\"private.uploaded_company_seal_snapshot(uuid)\",\"source_md5\":\"8d941e41fa11beadff7f36b95fd71035\",\"security_definer\":false,\"volatility\":\"v\",\"config\":[\"search_path=\\\"\\\"\"],\"owner\":\"postgres\",\"acl\":[{\"grantee\":\"postgres\",\"grantor\":\"postgres\",\"privilege\":\"EXECUTE\",\"grant_option\":false}]}],\"fixture\":{\"supabase/migrations/20260930054000_add_structured_company_qualification_exchange.sql\":\"1d7fe33b6f527a552a60c6ba0ce08a45cfd456f0e8374297aa37ae3f1a539bf3\",\"supabase/migrations/20261002104447_add_site_share_approval_flow.sql\":\"1d4a29c80894648e9098fc960c213cc1a4ca438d5e2a8a85bb10883ac0e6f052\",\"supabase/migrations/20261001214248_add_company_delivery_save_state.sql\":\"69fcaeda74bc8805d3a10d47746ea4f90f48990455d44b2208f8431dce74e8fd\",\"docs/review/site-order-compatibility/pinned-consumers.json\":\"b514d67f2c848c04e94ce84df8671c26f3842b5a67719a980190ed86c2ba45a7\",\"tool/site_order_target_composition/verify.mjs\":\"261db874def20e16c729a9443c68ab989c7a3638b26d7ea1a916db5d937f080d\"}}")
CONTRACT = 'sko.site_order.production_inputs.v1'
IMMUTABLE_C = '0c1a57402c666e991001814af5cdaa0f5bde138bf05e533c3e375bffb2d0e8f4'
MAX_BYTES = 16 * 1024 * 1024
# Actual current capture receipts have NOT been independently registered.
TRUSTED_CAPTURE_RECEIPTS = frozenset()

class Rejected(ValueError):
    pass

def strict_json(data):
    # Reuses the duplicate-key and nonfinite-number refusal contract from #1718.
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise Rejected('duplicate_json_key')
            result[key] = value
        return result
    def invalid(_):
        raise Rejected('invalid_json_number')
    try:
        return json.loads(data, object_pairs_hook=pairs, parse_constant=invalid)
    except (ValueError, UnicodeError, TypeError) as error:
        raise Rejected('invalid_json') from error

def exact_keys(value, expected):
    if not isinstance(value, dict) or set(value) != set(expected):
        raise Rejected('unexpected_shape')

def read_path(root, relative):
    root = Path(root).absolute()
    if any(p.is_symlink() for p in [root, *root.parents]):
        raise Rejected('symlink_root')
    if not isinstance(relative, str) or not relative or '\\' in relative or any(ord(c) < 32 for c in relative):
        raise Rejected('unsafe_path')
    part = PurePosixPath(relative)
    if part.is_absolute() or '..' in part.parts or part.as_posix() != relative:
        raise Rejected('unsafe_path')
    current = root
    for segment in part.parts:
        current = current / segment
        if current.is_symlink():
            raise Rejected('symlink_forbidden')
    if not current.is_file() or current.stat().st_size > MAX_BYTES:
        raise Rejected('missing_or_oversize_file')
    return current.read_bytes()

def read_ref(root, ref):
    exact_keys(ref, ('path', 'sha256'))
    data = read_path(root, ref['path'])
    if hashlib.sha256(data).hexdigest() != ref['sha256']:
        raise Rejected('artifact_integrity')
    return data

def source_units():
    units = []
    for row in PINS['sql']:
        units.append({'path': row['path'], 'commit': row['commit'],
                      'sha256': row.get('sha256', row.get('source_sha256')),
                      'mode': 'actor_only' if row['kind'] == 'extract-one-private-actor-only' else 'exact_source'})
    for row in PINS['edge']['sources']:
        units.append({'path': row['path'], 'commit': row['commit'], 'sha256': row['sha256'], 'mode': 'exact_source'})
    for name, row in PINS['edge']['renderer_files'].items():
        units.append({'path': 'tool/canonical_edge_wasm/' + name,
                      'commit': PINS['edge']['renderer_tool_commit'], 'sha256': row['sha256'], 'mode': 'exact_source'})
    return units

def qualify(root, manifest):
    report = {'contract': CONTRACT, 'source_qualified': False,
              'capture_qualified': False, 'deployable': False,
              'sql_executed': False, 'production_changed': False,
              'issues': [], 'missing': [], 'inventory': {
                  'source_units': source_units(), 'existing_relations': PINS['relations'],
                  'protected_exact_eight': PINS['protected'],
                  'proposed_relation_names': sorted({n for row in PINS['sql'] for n in row.get('declared_tables', [])}),
                  'proposed_function_names': sorted({n for row in PINS['sql'] for n in row.get('declared_functions', [])}),
                  'names_are_not_complete_function_signatures': True,
                  'dynamic_caller_closure_proven': False},
              'unresolved': ['actual_admission_owner_held_closure_and_drain',
                  'current_full_relation_function_namespace_default_acl_captures',
                  'complete_static_dynamic_and_edge_sql_caller_closure',
                  'real_auth_gateway_and_hosted_complete_cli_bundle',
                  'separate_production_approval_activation_and_real_partner_device_checks']}
    root = Path(root).absolute()
    if any(p.is_symlink() for p in [root, *root.parents]):
        report['issues'].append('symlink_root')
        return report
    try:
        exact_keys(manifest, ('contract', 'sources', 'captures', 'operational_evidence'))
        if manifest['contract'] != CONTRACT:
            raise Rejected('manifest_contract')
        sources = manifest['sources']
        if not isinstance(sources, list):
            raise Rejected('sources_type')
        expected = {(r['commit'], r['path']): r for r in source_units()}
        seen = set()
        for item in sources:
            exact_keys(item, ('commit', 'source_path', 'mode', 'artifact'))
            key = (item['commit'], item['source_path'])
            if key in seen:
                raise Rejected('duplicate_source')
            seen.add(key)
            if key not in expected:
                raise Rejected('unknown_or_superseded_source')
            pin = expected[key]
            if item['mode'] != pin['mode']:
                raise Rejected('financial_bundle_or_source_mode')
            data = read_ref(root, item['artifact'])
            if hashlib.sha256(data).hexdigest() != pin['sha256']:
                raise Rejected('source_pin_drift')
        report['missing'].extend('source:' + path for commit, path in sorted(set(expected) - seen))
        report['source_qualified'] = seen == set(expected)
        captures = manifest['captures']
        required = {'relations', 'functions', 'namespaces_default_acl', 'callers_and_edge_sql'}
        exact_keys(captures, required)
        for name in sorted(required):
            ref = captures[name]
            if ref is None:
                report['missing'].append('capture:' + name)
                continue
            data = read_ref(root, ref)
            # A caller-supplied hash or native:true is NOT an evidence trust root.
            if hashlib.sha256(data).hexdigest() not in TRUSTED_CAPTURE_RECEIPTS:
                raise Rejected('unregistered_actual_capture')
        # No current operator receipt exists in this source. Do not accept a boolean
        # or fixture receipt as maintenance authority. A later reviewed source change
        # must define the exact receipt contract before accepting any such evidence.
        if manifest['operational_evidence'] is not None:
            raise Rejected('unregistered_operational_evidence')
        report['missing'].append('operational:actual_held_closure_and_drain')
    except (Rejected, KeyError, TypeError, OSError) as error:
        report['issues'].append(str(error) if isinstance(error, Rejected) else 'invalid_input')
        report['source_qualified'] = False
    return report

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-root', required=True, type=Path)
    parser.add_argument('--manifest', default='manifest.json')
    args = parser.parse_args()
    try:
        manifest = strict_json(read_path(args.input_root, args.manifest))
        result = qualify(args.input_root, manifest)
    except (Rejected, OSError):
        result = {'deployable': False, 'source_qualified': False, 'issues': ['manifest_unreadable']}
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result.get('source_qualified') else 2

if __name__ == '__main__':
    raise SystemExit(main())
