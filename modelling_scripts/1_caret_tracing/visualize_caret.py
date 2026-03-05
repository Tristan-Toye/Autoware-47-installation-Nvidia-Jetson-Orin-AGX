#!/usr/bin/env python3
"""
CARET Visualization Script
=============================================================================
Generates all possible visualizations from CARET trace data including:
- Callback metrics (frequency, period, latency)
- Communication metrics
- Path metrics (message flow, response time, chain latency)
- Scheduling visualizations

Usage: python3 visualize_caret.py [config_file]
=============================================================================
"""

import os
import sys
import yaml
from pathlib import Path

# CARET imports
try:
    from caret_analyze import Application, Architecture, Lttng
    from caret_analyze.plot import Plot, chain_latency
    from bokeh.plotting import output_file, save
    from bokeh.io import export_png
except ImportError as e:
    print(f"ERROR: Required package not found: {e}")
    print("Install with: pip install caret-analyze bokeh")
    sys.exit(1)

SCRIPT_DIR = Path(__file__).parent


def load_config(config_path=None):
    """Load analysis configuration."""
    if config_path is None:
        config_path = SCRIPT_DIR / "results" / "analysis_config.yaml"
    
    if not config_path.exists():
        print(f"ERROR: Config file not found: {config_path}")
        print("Run analyze_caret_results.sh first.")
        sys.exit(1)
    
    with open(config_path, 'r') as f:
        return yaml.safe_load(f)


def setup_output_dir(config):
    """Create graphs output directory."""
    graphs_dir = Path(config.get('graphs_dir', SCRIPT_DIR / 'graphs'))
    graphs_dir.mkdir(parents=True, exist_ok=True)
    return graphs_dir


def load_caret_data(config):
    """Load CARET trace data and architecture."""
    lttng_path = config['lttng_path']
    arch_file = config.get('architecture_file')
    
    print(f"Loading trace data from: {lttng_path}")
    lttng = Lttng(lttng_path, validate=False)
    
    if arch_file and Path(arch_file).exists():
        print(f"Loading architecture from: {arch_file}")
        arch = Architecture('yaml', arch_file)
    else:
        print("Creating architecture from trace data...")
        arch = Architecture('lttng', lttng_path)
    
    print("Creating application object...")
    app = Application(arch, lttng)
    
    return app, arch, lttng


def save_plot(plot, output_path, title):
    """Save a plot to file."""
    output_file(str(output_path))
    try:
        fig = plot.figure()
        fig.title.text = title
        save(fig)
        print(f"  Saved: {output_path}")
    except Exception as e:
        print(f"  ERROR saving {title}: {e}")


def visualize_callbacks(app, graphs_dir, lstrip_s=5, rstrip_s=2):
    """Generate callback-related visualizations."""
    print("\n--- Callback Visualizations ---")
    
    callbacks = app.get_callbacks('*')
    if not callbacks:
        print("  No callbacks found")
        return
    
    print(f"  Found {len(callbacks)} callbacks")
    
    # Callback frequency timeseries
    try:
        plot = Plot.create_frequency_timeseries_plot(callbacks)
        save_plot(plot, graphs_dir / "callback_frequency_timeseries.html", 
                  "Callback Frequency Timeseries")
    except Exception as e:
        print(f"  ERROR creating frequency timeseries: {e}")
    
    # Callback frequency histogram
    try:
        plot = Plot.create_frequency_histogram_plot(callbacks)
        save_plot(plot, graphs_dir / "callback_frequency_histogram.html",
                  "Callback Frequency Histogram")
    except Exception as e:
        print(f"  ERROR creating frequency histogram: {e}")
    
    # Callback period timeseries
    try:
        plot = Plot.create_period_timeseries_plot(callbacks)
        save_plot(plot, graphs_dir / "callback_period_timeseries.html",
                  "Callback Period Timeseries")
    except Exception as e:
        print(f"  ERROR creating period timeseries: {e}")
    
    # Callback period histogram
    try:
        plot = Plot.create_period_histogram_plot(callbacks)
        save_plot(plot, graphs_dir / "callback_period_histogram.html",
                  "Callback Period Histogram")
    except Exception as e:
        print(f"  ERROR creating period histogram: {e}")
    
    # Callback latency timeseries
    try:
        plot = Plot.create_latency_timeseries_plot(callbacks)
        save_plot(plot, graphs_dir / "callback_latency_timeseries.html",
                  "Callback Latency Timeseries")
    except Exception as e:
        print(f"  ERROR creating latency timeseries: {e}")
    
    # Callback latency histogram
    try:
        plot = Plot.create_latency_histogram_plot(callbacks)
        save_plot(plot, graphs_dir / "callback_latency_histogram.html",
                  "Callback Latency Histogram")
    except Exception as e:
        print(f"  ERROR creating latency histogram: {e}")


def visualize_communications(app, graphs_dir):
    """Generate communication-related visualizations."""
    print("\n--- Communication Visualizations ---")
    
    try:
        communications = app.get_communications('*', '*')
        if not communications:
            print("  No communications found")
            return
        
        print(f"  Found {len(communications)} communications")
        
        # Communication frequency
        try:
            plot = Plot.create_frequency_timeseries_plot(communications)
            save_plot(plot, graphs_dir / "communication_frequency_timeseries.html",
                      "Communication Frequency Timeseries")
        except Exception as e:
            print(f"  ERROR creating comm frequency: {e}")
        
        # Communication period
        try:
            plot = Plot.create_period_timeseries_plot(communications)
            save_plot(plot, graphs_dir / "communication_period_timeseries.html",
                      "Communication Period Timeseries")
        except Exception as e:
            print(f"  ERROR creating comm period: {e}")
        
        # Communication latency
        try:
            plot = Plot.create_latency_timeseries_plot(communications)
            save_plot(plot, graphs_dir / "communication_latency_timeseries.html",
                      "Communication Latency Timeseries")
        except Exception as e:
            print(f"  ERROR creating comm latency: {e}")
            
    except Exception as e:
        print(f"  ERROR getting communications: {e}")


def visualize_paths(app, arch, graphs_dir, lstrip_s=5, rstrip_s=2):
    """Generate path-related visualizations."""
    print("\n--- Path Visualizations ---")
    
    try:
        # Search for paths
        paths = arch.search_paths('*', '*')
        if not paths:
            print("  No paths found")
            return
        
        print(f"  Found {len(paths)} paths")
        
        # Visualize first few paths (limit to avoid too many files)
        for i, path_info in enumerate(paths[:10]):
            try:
                path = app.get_path(path_info.path_name)
                
                # Message flow
                try:
                    plot = Plot.create_message_flow_plot(path)
                    save_plot(plot, graphs_dir / f"path_{i}_message_flow.html",
                              f"Message Flow: {path_info.path_name}")
                except Exception as e:
                    print(f"    ERROR message flow: {e}")
                
                # Response time histogram
                try:
                    plot = Plot.create_response_time_histogram_plot(path)
                    save_plot(plot, graphs_dir / f"path_{i}_response_time.html",
                              f"Response Time: {path_info.path_name}")
                except Exception as e:
                    print(f"    ERROR response time: {e}")
                
                # Chain latency
                try:
                    chain_latency(path, granularity='node', 
                                  lstrip_s=lstrip_s, rstrip_s=rstrip_s)
                except Exception as e:
                    print(f"    ERROR chain latency: {e}")
                    
            except Exception as e:
                print(f"  ERROR processing path {i}: {e}")
                
    except Exception as e:
        print(f"  ERROR searching paths: {e}")


def visualize_scheduling(app, graphs_dir):
    """Generate scheduling visualizations."""
    print("\n--- Scheduling Visualizations ---")
    
    try:
        callbacks = app.get_callbacks('*')
        if not callbacks:
            print("  No callbacks for scheduling visualization")
            return
        
        # Limit to first 20 callbacks for readability
        callbacks_subset = callbacks[:20]
        
        plot = Plot.create_callback_scheduling_plot(callbacks_subset)
        save_plot(plot, graphs_dir / "callback_scheduling.html",
                  "Callback Scheduling")
    except Exception as e:
        print(f"  ERROR creating scheduling plot: {e}")


def main():
    """Main entry point."""
    print("=" * 60)
    print("CARET Visualization Script")
    print("=" * 60)
    
    # Load configuration
    config_path = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    config = load_config(config_path)
    
    lstrip_s = config.get('lstrip_s', 5)
    rstrip_s = config.get('rstrip_s', 2)
    
    # Setup output directory
    graphs_dir = setup_output_dir(config)
    print(f"Output directory: {graphs_dir}")
    
    # Load CARET data
    app, arch, lttng = load_caret_data(config)
    
    # Generate visualizations
    visualize_callbacks(app, graphs_dir, lstrip_s, rstrip_s)
    visualize_communications(app, graphs_dir)
    visualize_paths(app, arch, graphs_dir, lstrip_s, rstrip_s)
    visualize_scheduling(app, graphs_dir)
    
    print("\n" + "=" * 60)
    print("Visualization complete!")
    print(f"Graphs saved to: {graphs_dir}")
    print("=" * 60)


if __name__ == '__main__':
    main()
