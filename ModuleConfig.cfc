component {

	this.name         = "megaphone";
	this.author       = "Ortus Solutions";
	this.webUrl       = "https://github.com/coldbox-modules/megaphone";
	this.dependencies = [ "qb", "str" ];
	this.cfmapping    = "megaphone";

	function configure() {
		settings = {
			"channels": {}
		};

		binder.getInjector().registerDSL( "megaphone", "#moduleMapping#.dsl.MegaphoneDSL" );
	}

	function onLoad() {
		variables.wirebox.getInstance( "NotificationService@megaphone" )
			.registerChannels( settings.channels ?: {} );
	}

}
