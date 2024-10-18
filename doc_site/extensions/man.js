/* Example use
 *
 * man:page[N,external]
 *
 *  N: section
 *  external: optional arg, links to external man page
 *
 */
module.exports = function(registry) {
    registry.inlineMacro('man', function() {
        var self = this
        self.process(function (parent, target, attrs) {
            let section = attrs.$positional[0] === undefined ? '' : attrs.$positional[0];
            let internal = attrs.$positional[1] === undefined ? true : false
            const attributes = {}
            const content = `${target}(${section})`
            let url
            if (internal) {
                url = `${target}.${section}.html`
            } else {
                url = `https://manpages.ubuntu.com/man${section}/${target}.${section}.html`
            }
            return self.createInline(parent, 'anchor',
                                     content, { type: 'link', target: url, attributes })
        })
    })
}

