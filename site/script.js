const recipeButtons = [...document.querySelectorAll(".recipe-option")]
const layoutButtons = [...document.querySelectorAll(".layout-option")]
const status = document.querySelector("#demo-status")

function select(buttons, selected) {
  for (const button of buttons) {
    const isSelected = button === selected
    button.classList.toggle("is-selected", isSelected)
    button.setAttribute("aria-pressed", String(isSelected))
  }
}

function updateStatus() {
  const recipe = document.querySelector(".recipe-option.is-selected")?.dataset.recipe
  const layout = document.querySelector(".layout-option.is-selected")?.dataset.layout

  if (status && recipe && layout) {
    status.textContent = `${recipe} selected with ${layout} layout.`
  }
}

for (const button of recipeButtons) {
  button.addEventListener("click", () => {
    select(recipeButtons, button)
    updateStatus()
  })
}

for (const button of layoutButtons) {
  button.addEventListener("click", () => {
    select(layoutButtons, button)
    updateStatus()
  })
}
