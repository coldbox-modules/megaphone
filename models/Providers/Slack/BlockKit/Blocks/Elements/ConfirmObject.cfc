component {

    /**
     * A plain_text-only text object that defines the dialog's title.
     *
     * Maximum length for this field is 100 characters.
     */
    property name="_title" type="PlainTextOnlyTextObject";

    /**
     * A text object that defines the explanatory text that appears in the confirm dialog.
     *
     * Maximum length for the text in this field is 300 characters.
     */
    property name="_text" type="TextObject";

    /**
     * A plain_text-only text object to define the text of the button that confirms the action.
     *
     * Maximum length for the text in this field is 30 characters.
     */
    property name="_confirm" type="PlainTextOnlyTextObject";

    /**
     * A plain_text-only text object to define the text of the button that cancels the action.
     *
     * Maximum length for the text in this field is 30 characters.
     */
    property name="_deny" type="PlainTextOnlyTextObject";

    /**
     * Defines the color scheme applied to the confirm button.
     *
     * A value of "danger" will display the button with a red background on desktop, or red text on mobile.
     * A value of "primary" will display the button with a green background on desktop, or blue text on mobile.
     *
     * If this field is not provided, the default value is "primary".
     */
    property name="_style";

    /**
     * Create a new confirm object instance.
     */
    public ConfirmObject function init( string text = "Please confirm this action." ) {
        variables.title( "Are you sure?" );
        variables.text( arguments.text );
        variables.confirm( "Yes" );
        variables.deny( "No" );
        return this;
    }

    /**
     * Set the title of the confirm object.
     */
    public PlainTextOnlyTextObject function title( required string title ) {
        variables._title = new PlainTextOnlyTextObject( text = title, maxLength = 100 );
        return variables._title;
    }

    /**
     * Set the text of the confirm object.
     */
    public TextObject function text( required string text ) {
        variables._text = new TextObject( text = arguments.text, maxLength = 300 );
        return variables._text;
    }

    /**
     * Set the confirm button label of the confirm object.
     */
    public PlainTextOnlyTextObject function confirm( required string label ) {
        variables._confirm = new PlainTextOnlyTextObject( text = arguments.label, maxLength = 30 );
        return variables._confirm;
    }

    /**
     * Set the deny button label of the confirm object.
     */
    public PlainTextOnlyTextObject function deny( required string label ) {
        variables._deny = new PlainTextOnlyTextObject( text = arguments.label, maxLength = 30 );
        return variables._deny;
    }

    /**
     * Marks the confirm dialog as dangerous.
     */
    public ConfirmObject function danger() {
        variables._style = "danger";
        return this;
    }

    public struct function getMemento() {
        var memento = {
            "title": variables._title.getMemento(),
            "text": variables._text.getMemento(),
            "confirm": variables._confirm.getMemento(),
            "deny": variables._deny.getMemento()
        };

        if ( !isNull( variables._style ) ) {
            memento[ "style" ] = variables._style;
        }

        return memento;
    }

}
