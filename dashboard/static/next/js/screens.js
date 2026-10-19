/* Screen registry: one line per screen. Sections become the dock, screens the sub-tabs, the hash and the lazy import. */
export const SECTIONS = [
  { id: "machine", name: "Machine", icon: '<rect x="3" y="4" width="18" height="12" rx="1.5"/><path d="M8 20h8M12 16v4M7 12l3-3 2 2 4-4"/>' },
  { id: "agents", name: "Agents", icon: '<path d="M5 14a7 7 0 0 1 14 0v3a3 3 0 0 1-3 3H8a3 3 0 0 1-3-3z"/><path d="M9 7 7.5 3.5M15 7l1.5-3.5"/><circle cx="9.5" cy="13" r="1.2"/><circle cx="14.5" cy="13" r="1.2"/>' },
  { id: "library", name: "Library", icon: '<path d="M4 5h5v15H4zM10 5h4v15h-4z"/><path d="m15.5 5.6 3.9-1 3.6 14.5-3.9 1z"/>' },
  { id: "voice", name: "Voice", icon: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21M8.5 21h7"/>' },
];
export const SCREENS = [
  { id: "eye", sec: "machine", name: "Overview", load: "./screens/overview.js" },
  { id: "vitals", sec: "machine", name: "Vitals", load: "./screens/vitals.js" },
  { id: "services", sec: "machine", name: "Services", shape: "rain", load: "/static/js/screens/services.js" },
  { id: "sites", sec: "machine", name: "Sites", shape: "stars", load: "/static/js/screens/sites.js" },
  { id: "todo", sec: "machine", name: "To do", shape: "wave", load: "/static/js/screens/todo.js" },
  { id: "agents", sec: "agents", name: "Court", load: "./screens/court.js" },
  { id: "roster", sec: "agents", name: "Roster", load: "./screens/roster.js" },
  { id: "docs", sec: "library", name: "Docs", shape: "sheets", load: "/static/js/screens/docs.js" },
  { id: "files", sec: "library", name: "Files", shape: "sheets", load: "/static/js/screens/files.js" },
  { id: "style", sec: "library", name: "Style", shape: "swatch", load: "/static/js/screens/style.js" },
  { id: "record", sec: "voice", name: "Record", load: "./screens/record.js" },
  { id: "pronunciation", sec: "voice", name: "Pronunciation", load: "./screens/pron.js" },
];
