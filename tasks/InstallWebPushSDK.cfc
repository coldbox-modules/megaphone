/** Explicit optional dependency installation; normal notification consumers do not need this task. */
component {

    function run( string directory = "./resources/java/webpush" ) {
        var targetDirectory = fileSystemUtil.resolvePath( arguments.directory );
        var target = targetDirectory & "/zerodep-web-push-java-2.1.5.jar";
        var checksum = "1337acba24004f2a702275b676eb3862e402c8775d3031b26464f0b18d3ba989";
        if ( fileExists( target ) && lCase( hash( fileReadBinary( target ), "SHA-256" ) ) == checksum ) {
            print.line( "Verified Web Push SDK 2.1.5 is already installed." );
            return;
        }
        var response = {};
        http
            url="https://repo.maven.apache.org/maven2/com/zerodeplibs/zerodep-web-push-java/2.1.5/zerodep-web-push-java-2.1.5.jar"
            method="GET"
            timeout="30"
            getAsBinary="yes"
            result="response";
        if (
            val( response.statusCode ) != 200 || !isBinary( response.fileContent ) || lCase(
                hash( response.fileContent, "SHA-256" )
            ) != checksum
        ) {
            throw(
                type = "Megaphone.Push.SDKVerificationFailed",
                message = "The pinned Web Push SDK could not be verified."
            );
        }
        if ( !directoryExists( targetDirectory ) ) {
            directoryCreate( targetDirectory, true );
        }
        fileWrite( target, response.fileContent );
        print.line( "Installed verified Web Push SDK 2.1.5." );
    }

}
