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

## The map

The Scene view (Ctrl+2, or Cmd+2 on macOS) shows the mission's map. **Top**, **Side** and
**Front** look at it from above, from the side and from the front; the note in the map's corner
says which way its axes point. Ships show as arrows that point the way they start, and nav points,
waypoints and points, such as where ships jump in, as diamonds, in their flight groups' colours.
Planets, the sun and nebulae show as faint discs. The scale in the corner is one cell of the grid.

A mission opens fitted to its ships and markers, leaving out the planets and the sun, which lie far
off. Many of the game's missions take place in several areas millions of units apart, so they open
as an overview: things that would overlap on the screen show as one round mark with how many it
holds, named after its most important thing.

- Drag the map to move it, and scroll to zoom in and out around the pointer. **Fit**, or a double
  click on an empty part of the map, shows the whole mission again.
- Point at a numbered mark to list what it holds, and click it to zoom in to them. Where its
  things lie on the same spot, the click lists them instead, to pick one.
- Names go where they have room, the selection's and the player's first. They never cover the
  legend, the scale or the other notes on the map, and keep off the routes where they can. Point at
  a mark to see a name that has no room.
- Click a ship or a marker to select it: the inspector shows it, and the map marks it with its
  place. Drag it to move where it starts: its `position` changes in the source when you let go, as
  one step of Undo. Hold Shift to snap to 100. A click on an empty part of the map clears the
  selection.
- **Ranges** rings each nav point or waypoint a ShipReached trigger watches, at the 4000 the game
  watches within, and dots a ring where the script sets a flyback marker, at its range.
  **Curves** shows the curves the director's camera flies, with their points.
- **Routes** shows where the script sends each ship and flight group (see below).
- **Follow** keeps a ship in the middle of the map.
- Where the map doesn't show the player's start, a note at its edge points to it.

**Live** and **Orders** show where the ships are and what they do in the running game, and come
with the live scene ([#21](https://github.com/OpenReliant/openreliant-editor/issues/21)).

### Routes

A route links the places the script sends a ship or a flight group to, in its group's colour. A
dotted leg is one the ship flies (Fly and Escort), and a dashed leg one it jumps (Jump Out and Warp
Out). An arrowhead shows where each leg goes, and a small ring where the route starts. In an
overview, the player's route shows the order the mission visits its areas in.

- A route starts where its ship starts, or a group's where its first ship starts. A ship the script
  brings in by a jump or a warp waits far off until then, so its route starts where it comes in.
- When a ship reaches a marker that a ShipReached trigger watches, the trigger's orders continue
  its route from there.
- A patrol route (`SetPatrolRoute`) goes round its flight group's waypoints in the order the mission
  lists them, and back to the first.
- Where an `if` sends a ship to different places, the route stops there, since either could be
  where it is next.
- A leg to or from a place off the map is a short stub that points the way.
- Select a ship, a group or a marker to make the routes it's on stand out, and click an empty part
  of the map to show them all alike again.

Routes read the script in the order the source gives its orders. A trigger runs when its condition
holds, so in the game a ship may take a route's legs in another order. The live scene will show
where ships really go.
