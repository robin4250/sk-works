# Memory-only Apple successor readiness

The default-OFF preparation now rechecks the current application SDK session and isolated prepared session whenever readiness is read. An observed silent same-UID session replacement or expiry invalidates the result permanently, even if the old session is then restored. The event observer remains as an additional invalidation boundary.

Two regression cases exercise silent SDK state replacement without publishing to the injected Auth event stream. This does not supply global Auth write serialization, an unobserved A-B-A guarantee, credential persistence, or application session adoption. No public route, production Auth configuration, grants, password, identity or company data changes. CI, production and device verification remain separate.

Previous head 30aae843 preparation CI 40665735744 succeeded. These added cases require their own CI result.
