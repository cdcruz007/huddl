import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import 'signup_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentStep = 0;
  String? _selectedStage;
  final List<String> _selectedInterests = [];

  final List<String> _stages = [
    'Expecting',
    'Newborn (0-3 months)',
    'Baby (3-12 months)',
    'Toddler (1-3 years)',
    'Preschool (3-5 years)',
    'School age (5+ years)',
  ];

  final List<String> _interests = [
    'Playgroups',
    'Baby sleep tips',
    'Feeding advice',
    'Parenting hacks',
    'Activities for kids',
    'Mental health',
    'Fitness',
    'Cooking',
    'Education',
    'Travel with kids',
    'Fashion & style',
    'Home organisation',
  ];

  void _nextStep() {
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SignupScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.white,
      appBar: AppBar(
        backgroundColor: HuddlColors.white,
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() => _currentStep--);
                },
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
        title: Text(
          'Step ${_currentStep + 1} of 3',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: HuddlColors.textHint,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              // Progress bar
              Row(
                children: List.generate(3, (i) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                      decoration: BoxDecoration(
                        color: i <= _currentStep
                            ? HuddlColors.primary
                            : HuddlColors.gray200,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 32),
              // Content
              Expanded(
                child: _buildStepContent(),
              ),
              // Next button
              HuddlPrimaryButton(
                text: _currentStep < 2 ? 'Continue' : 'Create account',
                onPressed: _nextStep,
              ),
              if (_currentStep < 2) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _nextStep,
                  child: Text(
                    'Skip',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.textHint,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStageStep();
      case 1:
        return _buildInterestsStep();
      case 2:
        return _buildLocationStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildStageStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What stage of life\nare you at?',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: HuddlColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This helps us find the right community for you.',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: HuddlColors.textHint,
            ),
          ),
          const SizedBox(height: 24),
          ...List.generate(_stages.length, (index) {
            final stage = _stages[index];
            final isSelected = _selectedStage == stage;
            return GestureDetector(
              onTap: () => setState(() => _selectedStage = stage),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isSelected ? HuddlColors.peachLight : HuddlColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: isSelected
                      ? Border.all(color: HuddlColors.primary, width: 1.5)
                      : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        stage,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: HuddlColors.textDark,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check_circle,
                        color: HuddlColors.primary,
                        size: 24,
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInterestsStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What are you\ninterested in?',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: HuddlColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select all that apply. You can always change these later.',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: HuddlColors.textHint,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _interests.map((interest) {
              final isSelected = _selectedInterests.contains(interest);
              return HuddlChip(
                label: interest,
                isSelected: isSelected,
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedInterests.remove(interest);
                    } else {
                      _selectedInterests.add(interest);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where are you\nlocated?',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: HuddlColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We use this to find local groups and events near you.',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: HuddlColors.textHint,
            ),
          ),
          const SizedBox(height: 24),
          // Location search
          const HuddlSearchBar(
            hint: 'Search your suburb or postcode',
          ),
          const SizedBox(height: 16),
          // Use current location
          GestureDetector(
            onTap: () {},
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: HuddlColors.blueBackground,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.my_location,
                    color: HuddlColors.blue,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Use my current location',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: HuddlColors.blue,
                          ),
                        ),
                        Text(
                          'We\'ll find groups near you',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: HuddlColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: HuddlColors.blue,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
