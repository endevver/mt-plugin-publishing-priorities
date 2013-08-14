# Publishing Priorities plugin for Movable Type

The Movable Type Publish Queue prioritizes which pages to publish based on
template type. Entries and Index Templates are high priority; Monthly Archives
are low priority, for example. This rough prioritization helps to ensure that
the most important files are generally published first.

Within a given template type (and its given priority) there are circumstances
that could be better handled by fine-tuning, especially on a large site. For
example, in a default installation the "Main Index" and "Archive Index" Index
Templates are both the same priority, but the "Main Index" is clearly more
important.

This plugin provides the means to fine-tune a template's priority. Additionally,
this plugin provides an option to make a gross adjustment to the entire blog's
priority, useful to prioritize at a more global level.

[ ![Publishing Priorities blog-level screenshot](https://raw.github.com/endevver/mt-plugin-publishing-priorities/master/documentation/thumb.jpg) ](https://raw.github.com/endevver/mt-plugin-publishing-priorities/master/documentation/screenshot.png)

# Requirements

* This plugin only affects files published through the Publish Queue.
* Movable Type 4.x or 5.x


# Installation

To install this plugin follow the instructions found here:

http://tinyurl.com/easy-plugin-install


# Configuration & Use

Visit Settings > Publishing Priorities at the Blog and Website level. to adjust
priorities. This screen contains a list of all of the templates set to use the
Publish Queue. By default, each template is set to its default priority and can
be changed to a different priority. Additionally, a Blog/Website level priority
option can be set, to lend a higher or lower priority to a given blog relative
to all other blogs in the system. Be sure to click Save Priorities when done
making changes.

Visit Settings > Publish Priorities at the System level to see and adjust the
priority of blogs relative to each other, and to jump to each blog's Publishing
Priorities screen.

The [Publish Queue Manager](https://github.com/endevver/mt-plugin-pqmanager)
plugin is useful for monitoring the Publish Queue contents, including to see
how your reprioritization has effected the build order of everything on your
site.

## Default Priorities

Below are the default priorities set by Movable Type. A larger number equals a
higher priority.

* Priority 10: Entries and Pages used for the "permalink" tags. This means that
  if there are several templates of the Entry or Page Type, only the
  "preferred" template (with the checkbox next to the Type) is priority 10. If
  there is only one template used for Entries or Pages, it is always priority
  10.

* Priority 9: Index Templates with `index`, `default`, `atom`, and `feed` in
  their file name. `index.html` will receive priority 9, for example, while an
  Index Template outputting a file names `file.html` will not be priority 9.

* Priority 8: All other Index Templates. In the above example, `file.html` will
  be published with a priority of 8.

* Priority 5: Entries and Pages not used for the permalink. That is, if there
  are several templates of the Entry or Page Type, the non-preferred ones are
  published with a priority of 5.

* Priority 4: Daily Archives.

* Priority 3: Weekly Archives.

* Priority 2: Monthly Archives.

* Priority 1: Yearhly, Category, and Author Archives.


# License

This plugin is licensed under the same terms as Perl itself.

#Copyright

Copyright 2013, Endevver LLC. All rights reserved.
