<cfoutput>
	<h1 class="text-center text-4xl font-bold uppercase tracking-wider">📣 Megaphone Explorer 📣</h1>
    <hr class="my-8" />
    <section class="w-1/3">
        <header class="flex items-center">
            <img class="w-16 h-16" src="https://assets-global.website-files.com/621c8d7ad9e04933c4e51ffb/622b2930098c680e60fe39f7_mark.png" alt="Slack icon" />
            <h2 class="text-3xl">Slack</h2>
        </header>
        <form method="POST" action="#event.buildLink( "main/slack" )#" class="flex-1 flex flex-col space-y-8">
            <fieldset class="flex flex-col">
                <label for="to">Username / Channel</label>
                <input id="to" type="text" name="to" placeholder="##general" autocomplete="off" data-1p-ignore />
            </fieldset>
            <fieldset class="flex-1 flex flex-col">
                <label for="blockJSON">Slack Block JSON</label>
                <textarea id="blockJSON" rows="8" name="blockJSON" autocomplete="off" data-1p-ignore></textarea>
            </fieldset>
            <fieldset class="flex-1 flex flex-col">
                <label for="token">Token</label>
                <input id="token" type="text" name="token" autocomplete="off" data-1p-ignore />
            </fieldset>
            <button type="submit" class="px-8 py-4 bg-blue-600 text-white hover:bg-blue-500 transition hover:-translate-y-1 rounded-lg">
                Send
            </button>
        </form>
    </section>
</cfoutput>
