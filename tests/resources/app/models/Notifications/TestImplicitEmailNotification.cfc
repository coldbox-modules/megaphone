component extends="megaphone.models.BaseNotification" accessors="true" {

    property name="message";

    public array function via( notifiable ) {
        return [ "email" ];
    }

    public Mail function toEmail( notifiable, newMail ) {
        return newMail(
            from: "noreply@example.com",
            subject: "Megaphone Email Notification",
            type: "html",
            bodyTokens: { product: "ColdBox" }
        ).setBody( "
			<p>Thank you for downloading @product@, have a great day!</p>
		" )
    }

}
