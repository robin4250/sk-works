# Keep new phone registration preparing until SMS delivery is ready

User instruction: prioritize security; when SMS verification is unavailable, show phone registration as preparing. Based on pinned build15 main `045169174188262f05b17c38495359e1059ea03b`, separate follow-up only.

A public provider-enabled boolean is not proof that an SMS delivery provider is connected or that OTPs arrive. Production enrollment therefore defaults to OFF independently of provider advertisement. The account card clearly labels new phone registration as preparing and disables registration/OTP confirmation. The repository also refuses those two writes; hiding a button alone is insufficient. An explicit constructor opt-in is used only in the isolated pre-existing SMS-flow fixtures to retain their coverage; the production factory never enables it.

Verified phone evidence and existing verified-phone password eligibility are retained. Confirmed email still permits first-password setup without requiring phone registration. Google/Face ID, existing credentials, company membership, contact-only phone data, provider settings, phone login for already enrolled users, and secondary passwords are unchanged. No test-only enablement is presented as real SMS readiness.

Four regressions cover provider-advertised true with registration OFF, no SMS/verify writes, preserved existing verified phone and email/password usability. Existing synthetic SMS request/confirmation tests remain behind explicit fixture opt-in. Help distinguishes contact phone from ownership-verified login phone. Remote CI is required; no local Flutter/Dart or actual SMS/OTP/provider modification is performed.

Official contract: https://supabase.com/docs/guides/auth/phone-login . SMS delivery integration and real OTP/device verification remain operational prerequisites before enabling future enrollment. This candidate is not merged into the already running build15.
