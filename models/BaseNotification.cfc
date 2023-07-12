component accessors="true" {

	property name="id";

	property
		name  ="wireboxId"
		inject="wirebox:targetId"
		getter="false"
		setter="false";

	public array function via() {
		throw(
			type    = "Megaphone.Notification.MissingAbstractMethod",
			message = "The `via` method must be implemented in a concrete notification component."
		);
	}

	public BaseNotification function populate( struct properties = {} ) {
		for ( var key in arguments.properties ) {
			variables[ key ] = arguments.properties[ key ];
		}
		return this;
	}

	public any function routeForType(
		required string type,
		required any notifiable,
		required string channelName
	) {
		if ( !structKeyExists( variables, "to" & arguments.type ) ) {
			var routingMethodName = str().camel( "to_#arguments.type#" );
			throw(
				type    = "Megaphone.Notification.MissingRoutingMethod",
				message = "The `#routingMethodName#` method must be implemented in order to route to the `#channelName#` channel."
			);
		}

		return invoke(
			this,
			"to" & arguments.type,
			{ "notifiable" : arguments.notifiable }
		);
	}

	public string function getNotificationType() {
		return variables.wireboxId;
	}

	private Str function str() provider="Str@Str" {
	}

}
