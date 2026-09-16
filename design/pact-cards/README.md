# Pact cards — ideas

Six ways to finish the cards on the Pacts screen. Open `index.html`.

What is wrong today: the card carries a title, a rule and a frequency inside a box tall
enough for three times that much, so the middle is empty and the card reads as a
placeholder. The frequency is also the only fact on it — the week the pact is a promise
about is invisible on that screen.

| Design | Fills the space with | Cost |
| --- | --- | --- |
| Week strip | Seven day pills, filled for days done, outlined for today | Needs this week's check-ins on the Pacts screen |
| Sticker | Outline, hard shadow and an oversized icon watermark | Decoration, not information |
| Rows, not tiles | Nothing — the row shrinks to its content | Loses the colour-block grid |
| Big number | The count, at display size | Still only frequency, just bigger |
| Progress ring | A ring around the pact icon | Smallest card; ring reads as a fraction, not as days |
| Who else | Crew faces and how many are in today | Needs per-pact membership, which the screen does not load |

The cheapest real fix is **week strip** or **big number**: both use data Home already
has. **Rows** is the one to pick if the grid itself is the problem.
