/** Builds and inspects the local publisher archive without publishing or changing versions. */
component {

    function run() {
        var root = fileSystemUtil.resolvePath( "." );
        var target = root & "/.tmp/megaphone-local-artifact.zip";
        directoryCreate( root & "/.tmp", true, true );
        var source = getInstance( "EndpointService" ).getEndpoint( "forgebox" ).createZipFromPath( root );
        fileCopy( source, target );
        var archive = createObject( "java", "java.util.zip.ZipFile" ).init( target );
        var names = [];
        var manifest = [];
        try {
            var entries = archive.entries();
            while ( entries.hasMoreElements() ) {
                var entry = entries.nextElement();
                var name = entry.getName();
                if ( names.find( name ) ) {
                    throw( message = "Artifact contains a duplicate path: " & name );
                }
                names.append( name );
                if ( !entry.isDirectory() ) {
                    var stream = archive.getInputStream( entry );
                    var bytes = createObject( "java", "java.io.ByteArrayOutputStream" ).init();
                    try {
                        stream.transferTo( bytes );
                        var digest = lCase( hash( bytes.toByteArray(), "SHA-256" ) );
                        if (
                            !fileExists( root & "/" & name ) || digest != lCase(
                                hash( fileReadBinary( root & "/" & name ), "SHA-256" )
                            )
                        ) {
                            throw( message = "Artifact content does not match its source: " & name );
                        }
                        manifest.append( { path: name, size: bytes.size(), sha256: digest } );
                    } finally {
                        stream.close();
                        bytes.close();
                    }
                }
            }
        } finally {
            archive.close();
        }
        for (
            var required in [
                "box.json",
                "ModuleConfig.cfc",
                "models/DeliveryStore.cfc",
                "models/DurableNotificationService.cfc",
                "models/Delegates/DatabaseNotificationService.cfc",
                "tasks/InstallWebPushSDK.cfc",
                "resources/database/migrations/2026_10_06_010002_complete_megaphone_recovery_allowance.cfc"
            ]
        ) {
            if ( !names.find( required ) ) {
                throw( message = "Artifact is missing required runtime file: " & required );
            }
        }
        for ( var name in names ) {
            if ( reFindNoCase( "(^|/)(tests|testbox|modules|\.git|\.tmp)/|\.jar$|(^|/)\.env$", name ) ) {
                throw( message = "Artifact contains an excluded development/dependency file: " & name );
            }
        }
        var descriptor = deserializeJSON( fileRead( root & "/box.json" ) );
        var receipt = {
            artifact: target,
            sha256: lCase( hash( fileReadBinary( target ), "SHA-256" ) ),
            files: names.len(),
            manifest: manifest,
            version: descriptor.version,
            status: "local-unreleased-source",
            published: false
        };
        fileWrite( root & "/.tmp/megaphone-local-artifact-receipt.json", serializeJSON( receipt ) );
        print.line( serializeJSON( receipt ) );
    }

}
