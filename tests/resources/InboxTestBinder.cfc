component extends="coldbox.system.ioc.config.Binder" {

    function configure() {
        variables.wireBox = {
            "scopeRegistration": { "enabled": true, "scope": "application", "key": "megaphoneInboxTestWireBox" }
        };
    }

}
