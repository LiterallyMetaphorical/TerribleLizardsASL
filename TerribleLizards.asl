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
			{ "Levels", true, "Levels", "Splits" },
				{ "SQ_Chp2_CINE_BrontoOpening_POV", true,  "The Attraction",            "Levels" },
				{ "lvl_Act3Part3",                  true,  "The Digsite",               "Levels" },
				{ "lvl_Act4Part4",                  true,  "The Fall",                  "Levels" },
				{ "SQ_lvl4_GoodEnding",             true,  "The Lair",                  "Levels" },
		{ "Debug", false, "Debug", null },
			{ "Level",                      false, "Level",                 "Debug" },
			{ "Loading",                    false, "Loading",               "Debug" },
			{ "Tags",                       false, "Game state tags",       "Debug" },
			{ "Objective",                  false, "Objective",             "Debug" },
			{ "Cutscene",                   false, "Cutscene",              "Debug" },
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
		vars.Utils = vars.Uhara.CreateTool("UnrealEngine", "Utils");

		// GameEngine.GameInstance(10A8) -> GI_TL_GameInstance_C: current level(298), Current Objective(314),
		// game state tag(528) GameplayTags: data(528), Num(530)
		vars.Resolver.Watch<ulong>("LevelFName", vars.Utils.GEngine, 0x10A8, 0x298);
		vars.Resolver.Watch<int>("Objective", vars.Utils.GEngine, 0x10A8, 0x314);
		vars.Resolver.Watch<ulong>("Tags", vars.Utils.GEngine, 0x10A8, 0x528);
		vars.Resolver.Watch<int>("TagCount", vars.Utils.GEngine, 0x10A8, 0x530);

		// GI.currently playing cutscene(268) -> LevelSequencePlayer.Sequence(290) -> name(18), "None" when no cutscene is playing.
		vars.Resolver.Watch<ulong>("CutsceneFName", vars.Utils.GEngine, 0x10A8, 0x268, 0x290, 0x18);
		vars.Resolver["CutsceneFName"].FailAction = MemoryWatcher.ReadFailAction.SetZeroOrNull;

		#region Text Component
		vars.SetTextIfEnabled = (Action<string, object>)((text1, text2) =>
		{
			if (settings[text1]) vars.SetText(text1, text2);
			else vars.RemoveText(text1);
		});
		#endregion

		current.Level = "";
		current.Cutscene = "";
		current.TagNames = "";
		current.Loading = false;
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

		// Loading screen: GAME STATE.Loading. The game also sets GAME STATE.Loading.FullLoad, .Loading.SaveState,
		// .Loading.Streaming (streaming during play) and GAME STATE.EnforcingStates (respawn).
		var tags = new List<string>();
		for (int i = 0; i < current.TagCount; i++) tags.Add(vars.Utils.FNameToString(game.ReadValue<uint>(new IntPtr((long)current.Tags + i * 8))));
		current.TagNames = string.Join(", ", tags);
		current.Loading = tags.Contains("GAME STATE.Loading");

		#region Debug Prints
		if (settings["Debug"])
		{
			if (old.Level != current.Level)                         { vars.SetTextIfEnabled("Level", current.Level);                                        print("Level? " + current.Level); }
			if (old.Loading != current.Loading)                     { vars.SetTextIfEnabled("Loading", current.Loading);                                    print("Loading? " + current.Loading.ToString()); }
			if (old.TagNames != current.TagNames)                   { vars.SetTextIfEnabled("Tags", current.TagNames);                                      print("Tags? " + current.TagNames); }
			if (old.Objective != current.Objective)                 { vars.SetTextIfEnabled("Objective", current.Objective);                                print("Objective? " + current.Objective); }
			if (old.Cutscene != current.Cutscene)                   { vars.SetTextIfEnabled("Cutscene", current.Cutscene);                                  print("Cutscene? " + current.Cutscene); }
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
		// New Game: control after the intro cutscene, when SQ_Chp1_CINE_Intro_FirstHalf stops
		return old.Cutscene == "SQ_Chp1_CINE_Intro_FirstHalf" && current.Cutscene != "SQ_Chp1_CINE_Intro_FirstHalf";
	}

	isLoading
	{
		return current.Loading;
	}

	split
	{
		string key = null;
		if (old.Objective != current.Objective) key = current.Level + "_" + current.Objective;
		if (old.Cutscene != current.Cutscene && (current.Cutscene == "SQ_Chp2_CINE_BrontoOpening_POV" || current.Cutscene == "SQ_lvl4_GoodEnding")) key = current.Cutscene;
		if (old.Level != current.Level) key = current.Level;

		if (key == null) return false;
		print("Split? " + key);
		return vars.CompletedSplits.Add(key) && settings[key];
	}

	exit
	{
		timer.IsGameTimePaused = true;
	}
