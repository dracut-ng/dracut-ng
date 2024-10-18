# Borrowed from
#  https://github.com/asciidoctor/asciidoctor-extensions-lab/blob/main/lib/man-inline-macro.rb

require 'asciidoctor/extensions' unless RUBY_ENGINE == 'opal'

include Asciidoctor

# An inline macro that generates links to related man pages.
#
# Usage:
#
#   man:gittutorial[7]
#
class ManInlineMacro < Extensions::InlineMacroProcessor
  use_dsl

  named :man
  name_positional_attributes 'volnum'

  def process parent, target, attrs
    text = manname = target
    suffix = ''
    target = %(#{manname}.html)
    if (volnum = attrs['volnum'])
      suffix = %((#{volnum}))
    end
    if parent.document.basebackend? 'html'
      parent.document.register :links, target
      node = create_anchor parent, text, type: :link, target: target
    elsif parent.document.backend == 'manpage'
      node = create_inline parent, :quoted, manname, type: :strong
    else
      node = create_inline parent, :quoted, manname
    end
    suffix ? (create_inline parent, :quoted, %(#{node.convert}#{suffix})) : node
  end
end

Extensions.register :uri_schemes do
  inline_macro ManInlineMacro
  # The following alias allows this macro to be used with the git man pages
  inline_macro ManInlineMacro, :linkgit
end
