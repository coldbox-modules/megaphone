component accessors="true" {

	property name="name"       type="string";
	property name="properties" type="struct";

	public string function getProviderName() {
		throw(
			type    = "Megaphone.Providers.MissingAbstractMethod",
			message = "The getProviderName() method must be implemented by the provider."
		);
	}

	public BaseNotification function notify( required any notifiable, required BaseNotification notification ) {
		throw(
			type    = "Megaphone.Providers.MissingAbstractMethod",
			message = "The notify() method must be implemented by the provider."
		);
	}

}
