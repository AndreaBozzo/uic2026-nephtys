module.exports = {
  uiPort: 1880,
  flowFile: "flows.json",
  credentialSecret: false,
  functionExternalModules: true,
  editorTheme: {
    projects: { enabled: false }
  },
  logging: {
    console: {
      level: "info",
      metrics: false,
      audit: false
    }
  }
};
