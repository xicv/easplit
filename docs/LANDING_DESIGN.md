# eaSplit landing design

The visual concept is stored in `docs/design/`:

- `landing-overview.png` — overall page order and rhythm
- `landing-hero.png` — first viewport composition
- `landing-workflow.png` — workflow and saved-recipe interaction
- `landing-trust.png` — privacy, compatibility, final action, and footer

## Design tokens

- Canvas: true near-black `#03070d`, deep footer `#010409`
- Text: crisp white `#f7f9fc`, muted blue-gray `#aeb9cb`
- Action: cobalt `#0a6cff`, focus blue `#4da1ff`
- Structure: blue-gray `#263850` hairlines
- Type: native macOS system sans, compact editorial display headings
- Radius: 10–12 points for controls, 22 points for major bounded surfaces
- Material: restrained translucency only on window and selection surfaces
- Spacing: 64-point desktop gutters with generous 76–112 point section rhythm

The page keeps all product copy and controls code-native. The window transition
is an HTML/CSS product illustration, not a screenshot or claim that the website
is running the macOS Accessibility workflow.

Product truth takes precedence over generated concept labels. The implementation
uses the shipping layout names **Columns**, **Rows**, **Three**, and **Focus**;
the ratio control in the app offers **50 / 50** and **60 / 40**.
