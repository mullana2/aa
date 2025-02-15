# setwd("~/Work/RD/MacroStab")
library(ggplot2)
library(GGally)
####
#### Server
####
shinyServer(function(input, output, session) {
  ##
  ## get the selected dataset
  ##
  df <- reactive({
    file <- input$file1
    if (is.null(file)){
      return(NULL)
    }
    read.csv(file$datapath, sep = input$sep)
  })
  
  #determining columns to be used for prediction
  discrete_cols <- reactive({
    df <- df()
    if (!is.null(df)) {
      cols <- vector()
      for (var in colnames(df)){
        if (length(unique(df[,var]))/length(df[,var]) > 0.05){
          cols <- c(cols, var) 
        }
      }
      cols
    }
  })
  
  #generates predictions
  predictions <- reactive({
    df <- df()
    if (is.null(df)) return(NULL) 
    if (!is.null(df)) {
      colnames <- discrete_cols()
      
      pairs <- combn(colnames, 2)
      pairs_list <- split(pairs, rep(1:ncol(pairs), each = nrow(pairs)))
      
      scag_fun <- function(dataset, col_names){
        scagnostics <- scagnostics(scale(dataset[col_names]))
        return(scagnostics[1:9])
      }
      string_fun <- function(col_names){
        return(paste(col_names[1], 'vs', col_names[2]))
      }
      output <- t(as.data.frame(lapply(pairs_list, scag_fun, dataset = df))) 
      rownames(output) <- lapply(pairs_list, string_fun)
      colnames(output) <- c("scag_num_1", "scag_num_2", "scag_num_3", "scag_num_4", "scag_num_5", "scag_num_6", "scag_num_7", "scag_num_8", "scag_num_9")
      
      scag_randomForest <- readRDS("model_4.2.18.rds")
      preds <- predict(scag_randomForest, newdata = output)
      pred_df<- as.data.frame(preds)
      pred_df$Relationship <- lapply(pairs_list, string_fun)
      pred_df <- pred_df %>% arrange(preds)
      
      return(pred_df)
    }
  })
  ##
  ## Preliminary objects 
  ##
  pObjects <- reactive({
    df <- df()
    data <- predictions()
    if (is.null(data)) return(NULL) 
    Levels <- levels(droplevels(data$preds))
    J <- length(Levels)
    Tabnames <- paste0(Levels) 
    list(J=J, Levels=Levels, Tabnames=Tabnames)
  })
  
  outputNodes <- reactive({ # output node names
    df <- df()
    preds <- predictions()
    pobjects <- pObjects()
    if (is.null(pobjects)) return(NULL)  
    J <- pobjects$J
    list(tnodes=paste0("tnode", LETTERS[1:J]), # table outputs
         pnodes=paste0("pnode", LETTERS[1:J])) # plot outputs
  })
  Selecteds <- reactive({ # return the values selected in the tabs (selectInput is defined in the tabs)
    dat <- df()
    preds <- predictions()
    if (is.null(dat)) return(NULL) 
    if (is.null(preds)) return(NULL) 
    J <- length(levels(droplevels(preds$preds)))
    selecteds <- rep(NA, J)
    for(i in 1:J){ 
      if (is.null(input[[paste0("sel",i)]])) return(NULL)
      match <- input[[paste0("sel",i)]]
      selecteds[i] <- strsplit(match, " vs ")
    }
    selecteds
  })

  ##
  ## make the UI in each tab - TRICK: use input$tab0 as the current counter, not i ! 
  ##
  observe({ 
    df <- df()
    preds <- predictions()
    pobjects <- pObjects()
  
    if (!is.null(pobjects)) {
      outnodes <- outputNodes()
      tnodes <- outnodes$tnodes
      pnodes <- outnodes$pnodes
      plot_types <- pobjects$Levels
      J <- pobjects$J
      output$dataplot <- renderPlot({
        df <- df()
        colnames <- discrete_cols()
        return(colnames)
      })
      
      pred_df <- predictions()
      dat <- df()
      
      ## tab 1, 2, ..., J
      I <- input$tab0
      for(i in 1:J){ 
        if(I==i){
          plot_type <- plot_types[as.numeric(I)] 
          #print(plot_type)
          dd <- droplevels(subset(pred_df, subset= preds == plot_type))
          #print(dd)
          output[[tnodes[i]]] <- renderTable({ # table in each tab 
            dd["Relationship"]
            
          })
          output[[pnodes[i]]] <- renderPlot({ # plot in each tab
            selecteds <- Selecteds()
            ggplot(data = dat) + geom_point(aes_string(x = selecteds[[as.numeric(I)]][1], y = selecteds[[as.numeric(I)]][2]))
          }, width=600, height=300)
        }
      }
    }
  })
  ##
  ## make the tabs 
  ##
  output$twotabs <- renderUI({
    df <- df()
    preds <- predictions()
    tabs <- list(NULL)
    ## temporary firsttab (disappears after data selection) :
    tabs[[1]] <- tabPanel("Begin", 
      h2("Choose a dataset to analyze!"), 
      value="0")
    ## permanent tabs : firsttab, 1, 2, ..., J, summarytab
    pobjects <- pObjects()
    if (!is.null(pobjects)) { 
      outnodes <- outputNodes()
      tnodes <- outnodes$tnodes
      pnodes <- outnodes$pnodes
      tabnames <- pobjects$Tabnames
      J <- length(tabnames)
      tabs[[1]] <- tabPanel("Plot Type:",
                          h3("Overview of Data"), 
                          h3("Click on the tabs to run the analysis for each test"),
                          plotOutput("dataplot"),
                          value="firsttab")
      for(i in 1:J){
        tabs[[i+1]] <- tabPanel(tabnames[i], 
                                fluidRow(
                                  column(3, h3(tabnames[i]),  tableOutput(tnodes[i])),
                                  column(4, 
                                         plotOutput(pnodes[i]),
                                         selectInput(paste0("sel",i), "Select relationship to view!", choices=preds[preds$preds == tabnames[i],][,2]))
                                ), value=i)
      }
    } 
    tabs$id <- "tab0"
    do.call(tabsetPanel, tabs)
  })
  #
})
  