# Design

Compact native utility. The most frequent action is adjusting the size of a single screen. Size gets a large percentage readout, a native slider, and one-point decrement/increment buttons. Source, output, stabilization, Recenter, and Start/Stop remain nearby. Sensor details and axis adjustments belong in an auxiliary diagnostics panel.

AppKit owns windows and controls. A Metal view owns the output surface. The app stays available in the menu bar when the control window closes.

Reference: the local Mac design skill's Things General preferences screenshot. Keep its calm surface, aligned native controls, spacing, and restrained dividers. Adapt to one pane and a prominent size value. Avoid tabs, unrelated categories, copied branding, and decorative cards.

Use system fonts, semantic system colors, a 4-point spacing rhythm, 24-point outer margins, native keyboard focus and accessible labels. Both Aqua and Dark Aqua are supported by semantic colors. The output view is black with a neutral grid and quiet cyan center markers.

States: no glasses, preview, live output, calibration in progress, missing capture permission, sensor unavailable, and display disconnected. Stop remains accessible in the menu bar with a global shortcut.

Refinement comparison: one checkbox, **Refined tracking**, sits beside the motion controls. It switches between the original and display-synchronized rendering paths without changing screen size, recentering, or requiring recalibration. Numeric timing measurements belong in Sensors, not the main controls. Do not hide controls automatically when output starts.

App icon, 0.2.1: front-facing satin-silver eyeglasses with teal lenses and a quiet horizontal lens highlight, centered on a charcoal midnight-blue field. The silhouette is legible at 32px. Generated through Magnific with GPT 2 high quality at 1024px; art direction applied through image-art-direction. Original source and exact prompt are in Assets. Native packaging supplies the rounded-square mask and transparent margins. The menu-bar icon remains a monochrome template symbol for native behavior.
