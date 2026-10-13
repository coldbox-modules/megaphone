component extends="cbq.models.BaseConfig" {

    public void function configure() {
        newConnection( "default" )
            .setDefaultQueue( "notifications" )
            .setProvider( "DBProvider@cbq" )
            .setProperties( { "datasource": "megaphone" } );
    }

}
