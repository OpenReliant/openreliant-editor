# Editing records

The inspector shows the record selected in the outline, or the one the source's cursor is in, as a
form. Each change is written into the source at once, as one step of Undo, and the source keeps its
own layout. The form can't change the source while it has problems: fix them first.

## The forms

- **Name** is the display name the game shows. **Declared as** is the name the source declares it
  under, which the script uses.
- A field that names a record, such as a ship's **Group**, lists the mission's records it can name.
  One that names a value of the game, such as a ship's **Type** or **Pilot**, lists the game's
  values, with a box to find one in a long list. `none` takes the field out of the table.
- A ship's or a marker's **Position** has a box for X, Y and Z, and its **Angles** a box for the
  yaw, the pitch and the roll, in degrees. Y points down.
- A number takes effect with Enter or by leaving its box. Escape puts back the value.
- A field the form can't show as a list or a number, such as a ship's **Launch**, shows its source,
  which you can type.
- A trigger's form sets what it **Watches**, its **Condition**, and the values of the condition's
  events it checks, how it **Repeats** and whether it's **Deferred**.

Each field's label tells what the field is when you rest the pointer on it.

## Adding records

The outline's + button, or Mission · Add a record, lists the records it can add: a ship, a nav
point, a waypoint, a flight group, a part, a trigger and a global. The new record goes after the
last one of its kind, under a name no record has, such as `ship_1`, and the form opens on it. A new
trigger watches nothing until you choose what it watches.

A name the source uses without declaring it shows in the Problems panel with **Declare**, which adds
a record under that name: choose what kind it is.

Squads, formations and curves list other records, and are written in the source.
