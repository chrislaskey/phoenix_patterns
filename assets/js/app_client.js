// Clients set `window.appClient = {setApiToken(token) {...}}` on the page
const clients = [
  () => window.appClient && (token => window.appClient.setApiToken(token))
]

export function findAppClient() {
  for (const find of clients) {
    const setApiToken = find()
    if (setApiToken) return setApiToken
  }
  return null
}

export const ClientConnect = {
  mounted() {
    const setApiToken = findAppClient()
    this.detected = () => this.pushEvent("client_detected", {available: Boolean(setApiToken)})
    this.detected()

    this.handleEvent("client_token", ({token}) => {
      if (!setApiToken) {
        this.pushEvent("connect_failed", {error: "No app client on this page"})
        return
      }

      Promise.resolve()
        .then(() => setApiToken(token))
        .then(() => this.pushEvent("connected", {}))
        .catch(error => this.pushEvent("connect_failed", {error: String(error)}))
    })
  },

  reconnected() {
    this.detected()
  }
}
