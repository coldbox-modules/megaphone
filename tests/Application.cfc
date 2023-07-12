component {

    this.name = "ColdBoxTestingSuite" & hash(getCurrentTemplatePath());
    this.sessionManagement  = true;
    this.setClientCookies   = true;
    this.sessionTimeout     = createTimeSpan( 0, 0, 15, 0 );
    this.applicationTimeout = createTimeSpan( 0, 0, 15, 0 );
    this.timezone = "UTC";

    // Turn on/off white space management
	this.whiteSpaceManagement = "smart";

    testsPath = getDirectoryFromPath( getCurrentTemplatePath() );
    this.mappings[ "/tests" ] = testsPath;
    rootPath = REReplaceNoCase( this.mappings[ "/tests" ], "tests(\\|/)", "" );
    this.mappings[ "/root" ] = rootPath;
    this.mappings[ "/testingModuleRoot" ] = listDeleteAt( rootPath, listLen( rootPath, '\/' ), "\/" );
    this.mappings[ "/megaphone" ] = listDeleteAt( rootPath, listLen( rootPath, '\/' ), "\/" );
    this.mappings[ "/app" ] = testsPath & "resources/app";
    this.mappings[ "/coldbox" ] = testsPath & "resources/app/coldbox";
    this.mappings[ "/testbox" ] = rootPath & "/testbox";

    this.datasource = "megaphone";

    function onApplicationStart() {
        param url.reloadDatabase = true;
    }

    function onRequestStart() {
        setting requestTimeout="180";

        // New ColdBox Virtual Application Starter
		request.coldBoxVirtualApp = new coldbox.system.testing.VirtualApp( appMapping = "/app" );

		// If hitting the runner or specs, prep our virtual app and database
		if ( getBaseTemplatePath().replace( expandPath( "/tests" ), "" ).reFindNoCase( "(runner|specs)" ) ) {
			request.coldBoxVirtualApp.startup();
		}

		// Reload for fresh results
		if( structKeyExists( url, "fwreinit" ) || structKeyExists( url, "reloadDatabase" )){
			if( structKeyExists( server, "lucee" ) ){
				pagePoolClear();
			}
			request.coldBoxVirtualApp.restart();
		}

        return true;
    }

    public void function onRequestEnd( required targetPage ) {
		request.coldBoxVirtualApp.shutdown();
	}


}
