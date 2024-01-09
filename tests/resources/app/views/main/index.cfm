<cfoutput>
<div class="container">
	<h1>Megaphone 📣</h1>

	<form method="POST" action="#event.buildLink( "notifications" )#">
		<input type="text" id="message" name="message" placeholder="Message" />
		<button type="submit">Send</button>
	</form>
</div>
</cfoutput>
