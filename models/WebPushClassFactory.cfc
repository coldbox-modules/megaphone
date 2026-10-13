/** Loads the pinned Web Push JAR dependency only when push is used. */
component {

    public WebPushClassFactory function init() {
        variables.jarPath = expandPath( "/megaphone/resources/java/webpush/zerodep-web-push-java-2.1.5.jar" );
        if (
            !fileExists( variables.jarPath ) ||
            lCase( hash( fileReadBinary( variables.jarPath ), "SHA-256" ) ) !=
            "1337acba24004f2a702275b676eb3862e402c8775d3031b26464f0b18d3ba989"
        ) {
            throw(
                type = "Megaphone.Push.ConfigurationUnavailable",
                message = "The Web Push SDK dependency is missing or does not match its verified checksum. Reinstall Megaphone with CommandBox."
            );
        }
        return this;
    }

    public any function create( required string className ) {
        return createObject( "java", arguments.className, variables.jarPath );
    }

}
