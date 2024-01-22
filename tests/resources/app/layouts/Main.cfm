<cfoutput>
<!doctype html>
<html lang="en">
<head>
	<!--- Metatags --->
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
	<meta name="description" content="Megaphone Explorer">
    <meta name="author" content="Ortus Solutions, Corp">

	<!---Base URL --->
	<base href="#event.getHTMLBaseURL()#" />

	<!--- Title --->
	<title>#event.getPrivateValue( "title", "📣 Megaphone Explorer 📣" )#</title>

	<link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Lato:ital,wght@0,100;0,300;0,400;0,700;0,900;1,100;1,300;1,400;1,700;1,900&display=swap" rel="stylesheet">
    <script src="https://cdn.tailwindcss.com?plugins=forms,typography"></script>
    <script>
        tailwind.config = {
          theme: {
            extend: {
              fontFamily: {
                'sans': ['Lato', 'sans-serif'],
              }
            }
          }
        }
      </script>
	  <script src="https://cdn.jsdelivr.net/npm/sweetalert2@11"></script>
</head>
<body class="m-8">
	<main>
		#view()#
	</main>
	<script>
		var #toScript( flash.get( "message", {} ), "flashMessage" )#;
		if ( flashMessage.text ) {
			Swal.fire({
				title: flashMessage.title,
				text: flashMessage.text,
				icon: flashMessage.type
			});
		}
	</script>
</body>
</html>
</cfoutput>
