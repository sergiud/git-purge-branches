# SPDX-FileCopyrightText: 2026 Sergiu Deitsch
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Provides the inline macro linkgit:<command>[<text>] of the documentation of
# Git, which shows a command of Git in bold. linkgit:git-branch[1] shows
# git-branch(1), and linkgit:git-branch[git branch -d] shows the given text.
# HTML links the command to its documentation on git-scm.com, while a manual
# page names it only.

require 'asciidoctor/extensions'

Asciidoctor::Extensions.register do
  inline_macro do
    named :linkgit
    name_positional_attributes 'text'

    process do |parent, target, attributes|
      text = attributes['text']
      label = text.match?(/\A\d+\z/) ? %(*#{target}*(#{text})) : %(*#{text}*)
      formatted = parent.apply_subs label, [:specialcharacters, :quotes]

      if parent.document.basebackend? 'html'
        create_anchor parent, formatted, type: :link, target: %(https://git-scm.com/docs/#{target})
      else
        create_inline parent, :quoted, formatted
      end
    end
  end
end
