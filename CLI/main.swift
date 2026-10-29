// The package builds the commands in SwitchboardCore; Xcode compiles the shipped tool as one module.
#if SWIFT_PACKAGE
    import SwitchboardCore
#endif

CommandLineTool.main()
