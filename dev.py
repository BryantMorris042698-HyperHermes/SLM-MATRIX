#!/usr/bin/env python3
"""
dev.py — unified CLI for SLM-MATRIX

Subcommands:
  mcts         Run Monte Carlo Tree Search extraction
  consistency  Run consistency checker on a trajectories file
  moa          Run Mixture-of-Agents interactive extraction
  pipeline     Run MCTS then consistency in one shot
"""

import subprocess
import sys
import os
from pathlib import Path

import typer
from rich.console import Console
from rich.panel import Panel
from dotenv import load_dotenv

load_dotenv()

app = typer.Typer(
    name="dev",
    help="SLM-MATRIX development CLI",
    add_completion=False,
)
console = Console()

ROOT = Path(__file__).parent


def _run(cmd: list[str]) -> int:
    result = subprocess.run(cmd, cwd=ROOT)
    return result.returncode


@app.command()
def mcts(
    query: str = typer.Option("", "--query", "-q", help="Material text to extract from"),
    simulations: int = typer.Option(4, "--simulations", "-s", help="MCTS simulation count"),
    depth: int = typer.Option(4, "--depth", "-d", help="Maximum search depth"),
    trajectories: int = typer.Option(3, "--trajectories", "-t", help="Best trajectories to output"),
    temperature: float = typer.Option(0.7, "--temperature", help="Sampling temperature"),
    max_tokens: int = typer.Option(2048, "--max-tokens", help="Max output tokens"),
):
    """Run Monte Carlo Tree Search extraction."""
    console.print(Panel("[bold cyan]SLM-MATRIX MCTS[/bold cyan]", expand=False))
    cmd = [
        sys.executable, str(ROOT / "MCTS_V7.py"),
        "--simulations", str(simulations),
        "--depth", str(depth),
        "--trajectories", str(trajectories),
        "--temperature", str(temperature),
        "--max_tokens", str(max_tokens),
    ]
    if query:
        cmd += ["--query", query]
    rc = _run(cmd)
    raise typer.Exit(rc)


@app.command()
def consistency(
    file: str = typer.Option("material_extraction_trajectories.txt", "--file", "-f", help="Trajectories file to check"),
    temperature: float = typer.Option(0.0, "--temperature", help="Regeneration temperature"),
    max_tokens: int = typer.Option(1024, "--max-tokens", help="Max tokens for regeneration"),
    model: str = typer.Option("", "--model", help="Override model name"),
    debug: bool = typer.Option(False, "--debug", help="Enable debug logging"),
):
    """Run consistency checker on a trajectories file."""
    console.print(Panel("[bold cyan]SLM-MATRIX Consistency[/bold cyan]", expand=False))
    cmd = [
        sys.executable, str(ROOT / "Consistency_V4.py"),
        "--file", file,
        "--temperature", str(temperature),
        "--max_tokens", str(max_tokens),
    ]
    if model:
        cmd += ["--model_name", model]
    if debug:
        cmd += ["--debug"]
    rc = _run(cmd)
    raise typer.Exit(rc)


@app.command()
def moa():
    """Run Mixture-of-Agents interactive extraction."""
    console.print(Panel("[bold cyan]SLM-MATRIX MoA[/bold cyan]", expand=False))
    rc = _run([sys.executable, str(ROOT / "MoA.py")])
    raise typer.Exit(rc)


@app.command()
def pipeline(
    query: str = typer.Argument(..., help="Material text to extract from"),
    simulations: int = typer.Option(4, "--simulations", "-s"),
    depth: int = typer.Option(4, "--depth", "-d"),
    trajectories: int = typer.Option(3, "--trajectories", "-t"),
    temperature: float = typer.Option(0.7, "--temperature"),
    max_tokens: int = typer.Option(2048, "--max-tokens"),
    trajectories_file: str = typer.Option("material_extraction_trajectories.txt", "--out", help="Trajectories output file"),
):
    """Run MCTS extraction then consistency check in one shot."""
    console.print(Panel("[bold cyan]SLM-MATRIX Pipeline: MCTS → Consistency[/bold cyan]", expand=False))

    console.print("\n[bold]Step 1/2:[/bold] Running MCTS...\n")
    mcts_cmd = [
        sys.executable, str(ROOT / "MCTS_V7.py"),
        "--query", query,
        "--simulations", str(simulations),
        "--depth", str(depth),
        "--trajectories", str(trajectories),
        "--temperature", str(temperature),
        "--max_tokens", str(max_tokens),
    ]
    rc = _run(mcts_cmd)
    if rc != 0:
        console.print(f"[red]MCTS failed (exit {rc}). Aborting pipeline.[/red]")
        raise typer.Exit(rc)

    if not Path(trajectories_file).exists():
        console.print(f"[red]Expected trajectories file not found: {trajectories_file}[/red]")
        raise typer.Exit(1)

    console.print("\n[bold]Step 2/2:[/bold] Running consistency check...\n")
    consistency_cmd = [
        sys.executable, str(ROOT / "Consistency_V4.py"),
        "--file", trajectories_file,
    ]
    rc = _run(consistency_cmd)
    raise typer.Exit(rc)


if __name__ == "__main__":
    app()
