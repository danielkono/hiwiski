# The home screen widgets (docs/development/home-widgets.md).
#
# Glance tells the widgets on a home screen apart by the class of their GlanceAppWidget:
# `HomeWidgets` asks for the placed widgets of one kind with `getGlanceIds(widget.javaClass)`.
# The four classes differ only in the kind they pass on, so R8 merged them into one — and
# then every kind was drawn into every widget, and the last one drawn, the Kanban column,
# showed everywhere. Only in a release: a debug build is not shrunk.
-keep class * extends de.danielkononov.hiwiski.widgets.HomeScreenWidget
