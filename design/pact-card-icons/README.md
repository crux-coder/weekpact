# Pact card — telling the button from the icon

Six corner treatments for the Pacts screen card. Open `index.html`. The card itself is
unchanged in all of them.

The problem: both top corners hold a 26px line icon, same ink, same weight. One is a
picture of the pact and one edits it, and nothing on the card says which is which.

| Design | How it separates them | Cost |
| --- | --- | --- |
| Action on a disc | The pencil gets a filled ink disc; the pact icon stays flat | Two icons still, just weighted |
| Overflow dots | Three dots are never data | Hides the action behind a menu |
| Icon joins the title | Pact icon moves beside the title, corner says EDIT in type | Long titles need to wrap |
| No button at all | The pencil goes; the card opens the pact | Edit is no longer visible |
| Action in the footer | Top row is the pact, bottom row the controls | Icon-only at this card width |
| Icon as watermark | The pact icon becomes scenery, so the only sharp icon is the button | Biggest visual change |

Cheapest: **action on a disc**. Least ambiguous: **overflow dots** or **no button at all**.
