#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod addons;

use tauri::{LogicalSize, Manager};

/// Share of the primary monitor's width the window opens at.
const WIDTH_FRACTION: f64 = 0.5;

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .setup(|app| {
            if let Some(window) = app.get_webview_window("main") {
                if let Ok(Some(monitor)) = window.primary_monitor() {
                    let scale = monitor.scale_factor();
                    let screen_width = monitor.size().width as f64 / scale;
                    let height = window
                        .inner_size()
                        .map(|s| s.height as f64 / window.scale_factor().unwrap_or(1.0))
                        .unwrap_or(700.0);
                    let _ = window.set_size(LogicalSize::new(screen_width * WIDTH_FRACTION, height));
                    let _ = window.center();
                }
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            addons::list_bundled_addons,
            addons::detect_addons_path,
            addons::set_addons_path,
            addons::list_installed_addons,
            addons::install_addons,
            addons::uninstall_addons,
        ])
        .run(tauri::generate_context!())
        .expect("error while running TK's Addon Manager");
}
