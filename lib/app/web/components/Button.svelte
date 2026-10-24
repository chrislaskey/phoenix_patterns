<!--
  Written by hand to mirror App.Web.CoreComponents.button/1
  in lib/app/web/components/core_components.ex. After changing the component, update this
  file to match and run `mix app.svelte --accept lib/app/web/components/Button.svelte`.
  heex-svelte: source=99af889b2aee output=none
-->
<script>
  // button/1 picks its classes and its tag in Elixir before the template,
  // which the generator can't follow. Like the component, it renders a link
  // when given href, navigate or patch and a button otherwise, and `class`
  // replaces the variant's classes. Outside LiveView navigate and patch are
  // plain links, and method is dropped, since nothing here makes a request.

  /**
   * @typedef {Object} Props
   * @property {any} [class]
   * @property {"primary"} [variant]
   * @property {import("svelte").Snippet<[]>} children
   */

  /** @type {Props & Record<string, any>} */
  let { class: class_, variant, children, ...rest } = $props()

  const variants = { primary: "btn-primary" }

  let classes = $derived(class_ ?? ["btn", variants[variant] ?? "btn-primary btn-soft"])
  let href = $derived(rest.href ?? rest.navigate ?? rest.patch)
  let { navigate, patch, method, ...linkRest } = $derived(rest)
</script>

{#if href}
  <a class={classes} {...linkRest} {href}>
    {@render children()}
  </a>
{:else}
  <button class={classes} {...rest}>
    {@render children()}
  </button>
{/if}
