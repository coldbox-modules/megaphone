component {

    function init( required string jarPath ) {
        variables.jarPath = arguments.jarPath;
        return this;
    }
    function create( required string className ) {
        return createObject( "java", arguments.className, variables.jarPath );
    }

}
