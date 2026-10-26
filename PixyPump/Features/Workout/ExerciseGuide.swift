import SwiftUI

/// Short "how to do it" notes for the exercises in the library:
/// what it works, how to do a rep, and the usual mistakes.
nonisolated struct ExerciseGuide: Sendable {
    let muscles: String
    let steps: [String]
    let mistakes: [String]

    /// Guide for an exercise name (nil for your own custom exercises).
    static func forExercise(_ name: String) -> ExerciseGuide? {
        all[name.lowercased()]
    }

    /// A YouTube search for good technique videos (opens in YouTube or Safari).
    static func videoURL(for name: String) -> URL? {
        var parts = URLComponents(string: "https://www.youtube.com/results")
        parts?.queryItems = [URLQueryItem(name: "search_query", value: "\(name) proper form tutorial")]
        return parts?.url
    }

    private static func g(_ muscles: String, _ steps: [String], _ mistakes: [String]) -> ExerciseGuide {
        ExerciseGuide(muscles: muscles, steps: steps, mistakes: mistakes)
    }

    private static let all: [String: ExerciseGuide] = [
        // Chest
        "bench press": g("Chest, front shoulders, triceps",
            ["Lie with eyes under the bar, feet flat, shoulder blades squeezed together.",
             "Grip a little wider than shoulders, unrack and lower the bar to your lower chest.",
             "Press up and slightly back until your arms are straight."],
            ["Bouncing the bar off your chest", "Elbows flared straight out to the sides", "Hips lifting off the bench"]),
        "incline bench press": g("Upper chest, front shoulders, triceps",
            ["Set the bench to about 30°. Shoulder blades back and down.",
             "Lower the bar to the top of your chest, just under the collarbones.",
             "Press straight up over your shoulders."],
            ["Bench set too steep (turns it into a shoulder press)", "Losing the arch in your upper back"]),
        "incline dumbbell press": g("Upper chest, front shoulders, triceps",
            ["Bench at about 30°. Kick the dumbbells up onto your knees, then lie back.",
             "Lower them to the sides of your upper chest, elbows about 45° from your body.",
             "Press up and slightly together without clanking them."],
            ["Going too heavy and cutting the range short", "Elbows flared straight out"]),
        "dumbbell bench press": g("Chest, front shoulders, triceps",
            ["Lie flat with the dumbbells over your chest, shoulder blades squeezed.",
             "Lower slowly until the dumbbells are level with your chest.",
             "Press back up, keeping wrists straight over elbows."],
            ["Dropping the weights fast at the bottom", "Wrists bent backwards"]),
        "machine press": g("Chest, front shoulders, triceps",
            ["Set the seat so the handles line up with the middle of your chest.",
             "Press forward until arms are almost straight.",
             "Return slowly until you feel a stretch in your chest."],
            ["Seat too high or low", "Letting the weight stack slam between reps"]),
        "cable fly": g("Chest",
            ["Set pulleys at shoulder height, step forward with a slight bend in your elbows.",
             "Bring your hands together in a wide hug in front of your chest.",
             "Open back up slowly until you feel a stretch."],
            ["Bending the elbows a lot (turns it into a press)", "Going too heavy and losing the stretch"]),
        "weighted dip": g("Chest, triceps, front shoulders",
            ["Support yourself on the bars with straight arms, weight hanging from a belt.",
             "Lean slightly forward and lower until your upper arms are about level with the bars.",
             "Push back up to straight arms."],
            ["Dropping too deep if your shoulders hurt", "Swinging the legs"]),
        "push-up": g("Chest, triceps, front shoulders, core",
            ["Hands a bit wider than shoulders, body in a straight line from head to heels.",
             "Lower your chest to just above the floor, elbows about 45° from your body.",
             "Push back up without letting your hips sag."],
            ["Hips sagging or piking up", "Only doing half the range"]),

        "pike push-up": g("Shoulders, triceps",
            ["Start in a push-up, then walk your feet in so your hips point up (an upside-down V).",
             "Bend your elbows and lower the top of your head towards the floor between your hands.",
             "Press back up."],
            ["Hips dropping (turns it into a normal push-up)", "Flaring elbows wide"]),

        // Back
        "inverted row": g("Upper back, lats, biceps",
            ["Hang under a bar or sturdy table at waist height, body straight, heels on the floor.",
             "Pull your chest up to the bar, squeezing shoulder blades together.",
             "Lower until your arms are straight."],
            ["Hips sagging", "Only pulling halfway"]),
        "pull-up": g("Back (lats), biceps",
            ["Hang from the bar with hands a bit wider than shoulders, palms facing away.",
             "Pull your chest towards the bar, driving elbows down to your sides.",
             "Lower all the way until your arms are straight."],
            ["Kicking or swinging", "Not going all the way down"]),
        "chin-up": g("Back (lats), biceps",
            ["Hang with hands shoulder-width apart, palms facing you.",
             "Pull until your chin clears the bar.",
             "Lower under control to straight arms."],
            ["Half reps", "Shrugging the shoulders up to the ears"]),
        "lat pulldown": g("Back (lats), biceps",
            ["Sit with thighs under the pads, grip a bit wider than shoulders.",
             "Pull the bar to your upper chest, leaning back only slightly.",
             "Let it rise slowly until your arms are straight."],
            ["Leaning far back and yanking with your body", "Pulling the bar behind your neck"]),
        "pendlay row": g("Upper and middle back, lats, biceps",
            ["Bend over until your back is almost parallel to the floor, bar on the floor.",
             "Pull the bar explosively to your lower chest.",
             "Put it back on the floor and reset each rep."],
            ["Rounding your lower back", "Standing up as you pull"]),
        "barbell row": g("Upper and middle back, lats, biceps",
            ["Hinge forward to about 45°, back flat, knees slightly bent.",
             "Pull the bar to your belly button, squeezing shoulder blades together.",
             "Lower until arms are straight."],
            ["Rounding your back", "Using momentum from your hips"]),
        "cable row": g("Middle back, lats, biceps",
            ["Sit tall with knees slightly bent and a straight back.",
             "Pull the handle to your belly, squeezing shoulder blades together.",
             "Let your arms go forward slowly while staying upright."],
            ["Rocking back and forth", "Shrugging the shoulders"]),
        "chest-supported row": g("Upper and middle back, rear shoulders",
            ["Lie face down on an incline bench with a dumbbell in each hand.",
             "Row the weights up, elbows travelling back past your body.",
             "Lower slowly to straight arms."],
            ["Lifting your chest off the pad", "Cutting the range short"]),
        "one-arm dumbbell row": g("Lats, middle back, biceps",
            ["One hand and knee on a bench, back flat, dumbbell in the other hand.",
             "Pull the dumbbell towards your hip.",
             "Lower until your arm is straight and your shoulder stretches."],
            ["Twisting your body to lift", "Pulling to the chest instead of the hip"]),
        "deadlift": g("Whole back side: hamstrings, glutes, back, grip",
            ["Stand with the bar over the middle of your feet, grip just outside your legs.",
             "Flat back, chest up, push the floor away and stand up with the bar close to your legs.",
             "Lower by pushing your hips back, keeping the bar close."],
            ["Rounding your lower back", "Bar drifting away from your legs", "Leaning back at the top"]),
        "face pull": g("Rear shoulders, upper back",
            ["Rope at face height. Grab it with palms facing in.",
             "Pull towards your face, splitting the rope and pointing elbows out and up.",
             "Return slowly."],
            ["Too heavy, so you lean back", "Pulling to the chest instead of the face"]),

        // Legs
        "squat": g("Thighs (quads), glutes, core",
            ["Bar on your upper back, feet about shoulder-width, toes slightly out.",
             "Brace your stomach, sit down between your heels until thighs are about parallel.",
             "Drive up through your whole foot, knees following your toes."],
            ["Knees caving in", "Heels lifting", "Rounding the lower back at the bottom"]),
        "front squat": g("Thighs (quads), glutes, upper back",
            ["Bar resting on the front of your shoulders, elbows high.",
             "Sit straight down, keeping your chest up.",
             "Stand back up without letting the elbows drop."],
            ["Elbows dropping so the bar rolls forward", "Leaning forward"]),
        "goblet squat": g("Thighs (quads), glutes, core",
            ["Hold one dumbbell upright against your chest, feet a bit wider than hips.",
             "Sit down between your heels, elbows inside your knees, chest up.",
             "Stand back up through your whole foot."],
            ["Heels lifting", "Rounding forward and dropping the chest"]),
        "bodyweight squat": g("Thighs (quads), glutes",
            ["Feet shoulder-width, arms out in front for balance.",
             "Sit down as low as you comfortably can, knees following your toes.",
             "Stand up and squeeze your glutes at the top."],
            ["Knees caving in", "Going too fast"]),
        "dumbbell romanian deadlift": g("Hamstrings, glutes, lower back",
            ["Stand holding dumbbells in front of your thighs, knees slightly bent.",
             "Push your hips back and slide the dumbbells down your legs until you feel a hamstring stretch.",
             "Squeeze your glutes to stand up."],
            ["Rounding the back", "Squatting down instead of hinging"]),
        "glute bridge": g("Glutes, hamstrings",
            ["Lie on your back, knees bent, feet flat near your bum.",
             "Push through your heels and lift your hips until your body is straight from knees to shoulders.",
             "Pause, then lower slowly."],
            ["Arching the lower back", "Pushing through the toes"]),
        "leg press": g("Thighs (quads), glutes",
            ["Feet shoulder-width in the middle of the platform, back flat on the pad.",
             "Lower until your knees are around 90° or a bit deeper.",
             "Press back up without locking your knees hard."],
            ["Lower back lifting off the pad", "Locking the knees at the top"]),
        "romanian deadlift": g("Hamstrings, glutes, lower back",
            ["Stand holding the bar, knees slightly bent.",
             "Push your hips back and slide the bar down your legs until you feel a hamstring stretch.",
             "Squeeze your glutes to stand back up."],
            ["Bending the knees more and more (turns into a squat)", "Rounding the back"]),
        "split squat": g("Thighs, glutes",
            ["Stand in a long stride, back heel up.",
             "Drop your back knee straight down towards the floor.",
             "Push up through your front foot."],
            ["Stance too short so the front heel lifts", "Leaning far forward"]),
        "lunge": g("Thighs, glutes",
            ["Step forward into a long stride.",
             "Lower your back knee towards the floor.",
             "Push back to the start and switch legs."],
            ["Front knee caving in", "Short, choppy steps"]),
        "leg extension": g("Thighs (quads)",
            ["Knees in line with the machine's pivot, pad on your lower shins.",
             "Straighten your legs fully and squeeze.",
             "Lower slowly."],
            ["Swinging the weight up", "Seat set wrong so knees aren't on the pivot"]),
        "lying hamstring curl": g("Hamstrings",
            ["Lie face down, pad just above your heels, knees just off the bench.",
             "Curl your heels towards your bum.",
             "Lower slowly to almost straight."],
            ["Hips lifting off the bench", "Dropping the weight fast"]),
        "seated hamstring curl": g("Hamstrings",
            ["Sit with the pad above your heels and the thigh pad snug.",
             "Pull your heels down and back as far as you can.",
             "Return slowly."],
            ["Using momentum", "Partial range"]),
        "hip thrust": g("Glutes, hamstrings",
            ["Upper back on a bench, bar over your hips, feet flat.",
             "Drive through your heels and lift your hips until your body is flat like a table.",
             "Lower with control."],
            ["Arching the lower back instead of using glutes", "Feet too far away"]),
        "calf raise": g("Calves",
            ["Balls of your feet on a step, heels hanging.",
             "Rise up as high as you can and pause.",
             "Lower slowly into a deep stretch."],
            ["Bouncing quickly", "Short range"]),

        // Shoulders
        "standing press": g("Shoulders, triceps, upper chest",
            ["Bar on the front of your shoulders, grip just outside shoulders, squeeze glutes.",
             "Press straight up, moving your head back slightly so the bar passes your face.",
             "Finish with the bar over your mid-foot, arms straight."],
            ["Leaning far back", "Pressing the bar forward instead of straight up"]),
        "seated dumbbell press": g("Shoulders, triceps",
            ["Sit upright with back support, dumbbells at shoulder height.",
             "Press up until your arms are straight.",
             "Lower to about ear height."],
            ["Arching off the backrest", "Lowering only halfway"]),
        "arnold press": g("Shoulders, triceps",
            ["Start with dumbbells in front of your shoulders, palms facing you.",
             "Rotate your palms forward as you press up.",
             "Reverse the turn on the way down."],
            ["Rushing the rotation", "Going too heavy"]),
        "lateral raise": g("Side shoulders",
            ["Stand with dumbbells at your sides, slight bend in the elbows.",
             "Raise your arms out to the sides up to shoulder height.",
             "Lower slowly."],
            ["Swinging with your body", "Shrugging up with the traps"]),
        "rear delt fly": g("Rear shoulders, upper back",
            ["Bend forward with a flat back, dumbbells hanging.",
             "Open your arms out to the sides, leading with the elbows.",
             "Lower slowly."],
            ["Squeezing shoulder blades too much (turns it into a row)", "Too heavy"]),
        "upright row": g("Side shoulders, traps",
            ["Hold a bar or dumbbells in front of your thighs, grip about shoulder-width.",
             "Pull up along your body to chest height, elbows leading.",
             "Lower slowly."],
            ["Pulling too high if it pinches your shoulders", "Narrow grip"]),

        // Arms
        "curl (barbell/dumbbell)": g("Biceps",
            ["Stand tall, elbows at your sides.",
             "Curl the weight up without moving your elbows forward.",
             "Lower all the way down slowly."],
            ["Swinging your back", "Not straightening your arms at the bottom"]),
        "incline dumbbell curl": g("Biceps (long head)",
            ["Sit back on an incline bench, arms hanging straight down.",
             "Curl up while keeping your upper arms still.",
             "Lower to a full stretch."],
            ["Bringing elbows forward", "Bench too upright"]),
        "hammer curl": g("Biceps, forearms",
            ["Hold dumbbells with palms facing each other.",
             "Curl up, keeping your thumbs pointing up.",
             "Lower slowly."],
            ["Swinging", "Elbows drifting forward"]),
        "preacher curl": g("Biceps",
            ["Upper arms flat on the pad, armpits snug against the top.",
             "Curl up until your forearms are vertical.",
             "Lower slowly almost to straight."],
            ["Dropping fast at the bottom (hard on the elbows)", "Lifting your arms off the pad"]),
        "overhead triceps": g("Triceps (long head)",
            ["Hold a dumbbell or rope overhead with both hands.",
             "Lower it behind your head by bending only your elbows.",
             "Straighten your arms back up."],
            ["Elbows flaring wide", "Arching your lower back"]),
        "triceps": g("Triceps",
            ["Keep your upper arms still by your sides.",
             "Straighten your elbows fully against the resistance.",
             "Return slowly."],
            ["Moving your shoulders", "Partial reps"]),
        "triceps pushdown": g("Triceps",
            ["Stand at a high cable, elbows tucked at your sides.",
             "Push the bar or rope down until your arms are straight.",
             "Let it come up to about chest height."],
            ["Elbows moving forward and back", "Leaning over the weight"]),
        "dumbbell skull crusher": g("Triceps",
            ["Lie on a bench, dumbbells straight up over your shoulders.",
             "Bend at the elbows to lower them beside your head.",
             "Straighten back up."],
            ["Elbows flaring out", "Moving the upper arms"]),
        "close-grip bench press": g("Triceps, chest",
            ["Like the bench press, but hands about shoulder-width.",
             "Lower to your lower chest with elbows close to your body.",
             "Press up."],
            ["Grip too narrow (hard on wrists)", "Elbows flaring"]),

        // Core
        "plank": g("Core",
            ["Forearms on the floor, elbows under shoulders.",
             "Body in a straight line, squeeze your glutes and stomach.",
             "Hold and breathe steadily."],
            ["Hips sagging", "Bum too high"]),
        "hanging leg raise": g("Lower abs, hip flexors",
            ["Hang from a bar with straight arms.",
             "Lift your legs (or knees) up by curling your pelvis.",
             "Lower slowly without swinging."],
            ["Swinging", "Only lifting the legs without curling the pelvis"]),
        "cable crunch": g("Abs",
            ["Kneel facing a high cable, rope by your head.",
             "Crunch down by rounding your spine, bringing elbows to your thighs.",
             "Rise back up slowly."],
            ["Pulling with your arms", "Bending at the hips instead of the spine"]),
        "ab wheel": g("Core",
            ["Kneel holding the wheel under your shoulders.",
             "Roll forward slowly while keeping your back flat.",
             "Pull back using your stomach."],
            ["Lower back sagging", "Going further than you can control"]),
    ]
}

/// The "How to do it" sheet for one exercise.
struct ExerciseGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let name: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let guide = ExerciseGuide.forExercise(name) {
                        section("Works", icon: .target) {
                            Text(guide.muscles).foregroundStyle(Color.ppText)
                        }
                        section("How to do it", icon: .list) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(guide.steps.enumerated()), id: \.offset) { i, step in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("\(i + 1)")
                                            .font(.pixel(DS.TextSize.footnote))
                                            .foregroundStyle(Color.ppOnAccent)
                                            .frame(width: 24, height: 24)
                                            .background(Color.brand, in: Circle())
                                        Text(step)
                                            .foregroundStyle(Color.ppText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        section("Avoid", icon: .warning) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(guide.mistakes, id: \.self) { mistake in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("·").foregroundStyle(Color.ppCarbs)
                                        Text(mistake)
                                            .foregroundStyle(Color.ppText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("This is your own exercise, so there's no written guide. Watch a video below, and add your own cues in the note on the exercise screen.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let url = ExerciseGuide.videoURL(for: name) {
                        Link(destination: url) {
                            HStack(spacing: 8) {
                                Image.pixel(.eye, size: 16)
                                Text("Watch a video")
                            }
                        }
                        .buttonStyle(.primary)
                        Text("Opens YouTube with technique videos for \(name). Start light and film yourself from the side to check your form.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func section<Content: View>(_ title: String, icon: PixelGlyph,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image.pixel(icon, size: 16).foregroundStyle(Color.brand)
                PPHeader(title)
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: DS.Radius.card)
    }
}
