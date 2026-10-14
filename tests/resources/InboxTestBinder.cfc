component extends="coldbox.system.ioc.config.Binder" {

    function configure() {
        variables.wireBox = {
            "scopeRegistration": { "enabled": true, "scope": "application", "key": "megaphoneInboxTestWireBox" },
            // Fixture injectors must not reuse application dependencies cached under the same mapping names.
            "transientInjectionCache": false
        };
    }

}
