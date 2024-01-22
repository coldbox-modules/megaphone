component extends="PlainTextOnlyTextObject" {

    /**
     * The formatting to use for this text object.
     *
     * Can be one of "plain_text" or "mrkdwn".
     */
    property name="type" type="string" default="plain_text";

    /**
     * Whether to skip any preprocessing / auto-conversion of URLs, conversation names, and certain mentions.
     *
     * Only applicable for mrkdwn text objects.
     */
    property name="_verbatim" type="boolean";

    /**
     * Set the title of the confirm object.
     */
    public TextObject function markdown() {
        variables.type = "mrkdwn";
        return this;
    }

    /**
     * Indicate that URLs, conversation names and certain mentions should not be auto-linked.
     *
     * Only applicable for mrkdwn text objects.
     */
    public TextObject function verbatim() {
        variables._verbatim = true;
        return this;
    }

    public struct function getMemento() {
        var memento = super.getMemento();
        memento[ "type" ] = variables.type;

        if ( variables.type != "mrkdwn" ) {
            return memento;
        }

        structDelete( memento, "emoji" );
        if ( !isNull( variables._verbatim ) ) {
            memento[ "verbatim" ] = variables._verbatim;
        }
        return memento;
    }

}
