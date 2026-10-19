// In your module (e.g., state.js)
export const state = {
  initial_render: true,
  // A flag to ensure we don't schedule more than one render per frame.
  isRenderScheduled: false,
  currentDepthNode: "",
};
