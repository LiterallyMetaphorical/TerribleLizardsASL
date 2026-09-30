	state("terrible_lizards-Win64-Shipping") {}

	startup
	{
		Assembly.Load(File.ReadAllBytes("Components/uhara10")).CreateInstance("Main");

		vars.Uhara.AlertLoadless();
		vars.Uhara.EnableDebug();

		#region setting creation
		dynamic[,] _settings =
		{
		{ "Splits", true, "Splits", null },
			{ "Story", true, "Story Demo", "Splits" },
				{ "lvl_DemoMAIN_2025_2",    true,  "Collect the Code Pages",            "Story" },
				{ "lvl_DemoMAIN_2025_13",   true,  "Walk through the gate into the Projector Room",              "Story" },
				{ "lvl_DemoMAIN_2025_7",    true,  "Unlock the Wooden Gate",              "Story" },
				{ "lvl_DemoMAIN_2025_10",   true,  "Make your way through the Exhibit",                          "Story" },
				{ "lvl_DemoMAIN_2025_40",   true,  "Restore Power to the Exhibit",                               "Story" },
				{ "StoryEnd",               true,  "Follow the Mascot",                                "Story" },
			{ "Gameplay", true, "Gameplay Demo", "Splits" },
				{ "Lvl2_DemoMAIN_2026_1",   true,  "Investigate the Cavern",                          "Gameplay" },
				{ "Lvl2_DemoMAIN_2026_2",   true,  "Find a Generator",                    "Gameplay" },
				{ "Lvl2_DemoMAIN_2026_3",   true,  "Open the Gate",                                "Gameplay" },
				{ "Lvl2_DemoMAIN_2026_4",   true,  "Head through the Tunnels",                                   "Gameplay" },
				{ "Lvl2_DemoMAIN_2026_6",   true,  "Climb to the Surface",                        "Gameplay" },
				{ "Lvl2_DemoMAIN_2026_7",   true,  "Run!",                                            "Gameplay" },
				{ "GameplayEnd",            true,  "Escape the Bronto",                               "Gameplay" },
		{ "Debug", false, "Debug", null },
			{ "Level",                      false, "Level",                 "Debug" },
			{ "Loading",                    false, "Loading",               "Debug" },
			{ "BetweenDemos",               false, "Between demos",         "Debug" },
			{ "Objective",                  false, "Objective",             "Debug" },
			{ "Cutscene",                   false, "Cutscene",              "Debug" },
			{ "EndVideo",                   false, "Gameplay end video",    "Debug" },
		};
		vars.Uhara.Settings.Create(_settings);
		#endregion

		#region TextComponent
		vars.lcCache = new Dictionary<string, LiveSplit.UI.Components.ILayoutComponent>();
		vars.SetText = (Action<string, object>)((text1, text2) =>
		{
			const string FileName = "LiveSplit.Text.dll";
			LiveSplit.UI.Components.ILayoutComponent lc;

			if (!vars.lcCache.TryGetValue(text1, out lc))
			{
				lc = timer.Layout.LayoutComponents.Reverse().Cast<dynamic>()
					.FirstOrDefault(llc => llc.Path.EndsWith(FileName) && llc.Component.Settings.Text1 == text1)
					?? LiveSplit.UI.Components.ComponentManager.LoadLayoutComponent(FileName, timer);

				vars.lcCache.Add(text1, lc);
			}

			if (!timer.Layout.LayoutComponents.Contains(lc)) timer.Layout.LayoutComponents.Add(lc);
			dynamic tc = lc.Component;
			tc.Settings.Text1 = text1;
			tc.Settings.Text2 = text2.ToString();
		});
		vars.RemoveText = (Action<string>)(text1 =>
		{
			LiveSplit.UI.Components.ILayoutComponent lc;
			if (vars.lcCache.TryGetValue(text1, out lc))
			{
				timer.Layout.LayoutComponents.Remove(lc);
				vars.lcCache.Remove(text1);
			}
		});
		#endregion

		vars.CompletedSplits = new HashSet<string>();
	}

	init
	{
		vars.Events = vars.Uhara.CreateTool("UnrealEngine", "Events");
		vars.Utils = vars.Uhara.CreateTool("UnrealEngine", "Utils");

		// GameEngine.GameInstance(10A8) -> GI_TL_GameInstance_C: current level(298), Current Objective(2D4),
		// game state tag(4E8) GameplayTags.Num(4F0). The only tag the game puts there is GAME STATE.Loading, while a loading screen is up.
		vars.Resolver.Watch<ulong>("LevelFName", vars.Utils.GEngine, 0x10A8, 0x298);
		vars.Resolver.Watch<int>("Objective", vars.Utils.GEngine, 0x10A8, 0x2D4);
		vars.Resolver.Watch<int>("GameStateTags", vars.Utils.GEngine, 0x10A8, 0x4F0);

		// GI.currently playing cutscene(268) -> LevelSequencePlayer.Sequence(290) -> name(18), "None" when no cutscene is playing.
		vars.Resolver.Watch<ulong>("CutsceneFName", vars.Utils.GEngine, 0x10A8, 0x268, 0x290, 0x18);
		vars.Resolver["CutsceneFName"].FailAction = MemoryWatcher.ReadFailAction.SetZeroOrNull;
		// Gameplay Demo end video (EndDemoSizzle.mp4), created on the frame the chase ends: WD_UI_DEMO_SizzleReelPlayer_C
		vars.Resolver.Watch<ulong>("EndVideo", vars.Events.InstancePtr("WD_UI_DEMO_SizzleReelPlayer_C", "WD_UI_DEMO_SizzleReelPlayer_C"));

		#region Text Component
		vars.SetTextIfEnabled = (Action<string, object>)((text1, text2) =>
		{
			if (settings[text1]) vars.SetText(text1, text2);
			else vars.RemoveText(text1);
		});
		#endregion

		current.Level = "";
		current.Cutscene = "";
		current.BetweenDemos = false;
	}

	update
	{
		vars.Uhara.Update();

		var level = vars.Utils.FNameToString((uint)(current.LevelFName & 0xFFFFFFFF));
		uint number = (uint)(current.LevelFName >> 32);
		if (!string.IsNullOrEmpty(level) && level != "None") current.Level = number == 0 ? level : level + "_" + (number - 1);

		var cutscene = vars.Utils.FNameToString((uint)(current.CutsceneFName & 0xFFFFFFFF));
		number = (uint)(current.CutsceneFName >> 32);
		current.Cutscene = number == 0 ? cutscene : cutscene + "_" + (number - 1);

		// Full demo run: pause timer from the Story end split until the next loading screen (Continue into the Gameplay Demo) ends
		if (old.Cutscene != current.Cutscene && current.Cutscene == "SQ_DemoEnd_2025") current.BetweenDemos = true;
		else if (old.GameStateTags > 0 && current.GameStateTags == 0) current.BetweenDemos = false;

		#region Debug Prints
		if (settings["Debug"])
		{
			if (old.Level != current.Level)                         { vars.SetTextIfEnabled("Level", current.Level);                                        print("Level? " + current.Level); }
			if (old.GameStateTags != current.GameStateTags)         { vars.SetTextIfEnabled("Loading", current.GameStateTags > 0);                          print("Loading? " + (current.GameStateTags > 0).ToString()); }
			if (old.BetweenDemos != current.BetweenDemos)           { vars.SetTextIfEnabled("BetweenDemos", current.BetweenDemos);                          print("BetweenDemos? " + current.BetweenDemos.ToString()); }
			if (old.Objective != current.Objective)                 { vars.SetTextIfEnabled("Objective", current.Objective);                                print("Objective? " + current.Objective); }
			if (old.Cutscene != current.Cutscene)                   { vars.SetTextIfEnabled("Cutscene", current.Cutscene);                                  print("Cutscene? " + current.Cutscene); }
			if (old.EndVideo != current.EndVideo)                   { vars.SetTextIfEnabled("EndVideo", current.EndVideo.ToString("X"));                    print("EndVideo? " + current.EndVideo.ToString("X")); }
		}
		#endregion
	}

	onStart
	{
		timer.IsGameTimePaused = true;
		timer.SetGameTime(TimeSpan.Zero);
		vars.CompletedSplits.Clear();
	}

	start
	{
		// Gameplay Demo: PLAY leaves the main menu. Story Demo: control after the intro cutscene, when SQ_Chp1_CINE_Intro_FirstHalf stops.
		return old.Level == "lvl_MainMenu" && current.Level == "Lvl2_DemoMAIN_2026"
			|| old.Cutscene == "SQ_Chp1_CINE_Intro_FirstHalf" && current.Cutscene != "SQ_Chp1_CINE_Intro_FirstHalf";
	}

	isLoading
	{
		return current.GameStateTags > 0 || current.BetweenDemos;
	}

	split
	{
		string key = null;
		if (old.Objective != current.Objective) key = current.Level + "_" + current.Objective;
		if (old.Cutscene != current.Cutscene && current.Cutscene == "SQ_DemoEnd_2025") key = "StoryEnd";
		if (old.EndVideo != current.EndVideo && current.EndVideo != 0UL) key = "GameplayEnd";

		if (key == null) return false;
		print("Split? " + key);
		return vars.CompletedSplits.Add(key) && settings[key];
	}

	exit
	{
		timer.IsGameTimePaused = true;
	}
